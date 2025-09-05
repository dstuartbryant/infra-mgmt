import json
from os import makedirs, path, rmdir
from typing import Tuple

import yaml
from jinja2 import Environment, FileSystemLoader

from .models import Account, AccountsList, InitIamParam, TerraformUserConfig
from .utils import quiet_terraform_output_json, rearrange_quiet_terraform_output_dict

CURR_DIR = path.dirname(path.abspath(__file__))
TEMPLATES_DIR = path.join(CURR_DIR, "templates")


class ConfigError(Exception):
    pass


def split_email(email: str) -> Tuple[str, str]:
    """Splits an email address into its addressee and domain parts to later faciliate
    plus+addressing (sub-addressing).

    Args:
        email (str): email address to split

    Returns:
        prefix (str): addressee portion of email address
        domain (str): address domain
    """
    if "@" not in email:
        raise ValueError("Unexpected email address format found.")

    esplt = email.split("@")
    prefix = esplt[0]
    domain = esplt[1]
    return prefix, domain


def load_terraform_user_config(config_path: str) -> TerraformUserConfig:
    """Loads user config files and performs cross check validations.
    Args:
        config_path (str): Path to user config yaml file.

    Returns:

    """
    config_data = yaml.safe_load(open(config_path, "r"))
    tuc = TerraformUserConfig(**config_data)

    # Cross-check project names and those in group_accounts
    for group, group_accounts in tuc.group_accounts.items():
        for acc in group_accounts:
            if acc not in tuc.projects:
                raise ValueError(
                    f"Account {acc} for group {group} not in projects list. Expecting "
                    f"one of {', '.join(tuc.projects)}"
                )

    # Cross-check user assigned groups to those listed in groups
    for user in tuc.unclass_users:
        for grp in user.groups:
            if grp not in tuc.groups:
                raise ValueError(
                    f"Group {grp} for user {user.username} not in groups list. "
                    f"Expecting one of {', '.join(tuc.groups)}"
                )

    return tuc


def generate_accounts_config(config_path: str, accounts_json_path: str):
    """Generates an accounts configuration dictionary in a format that Terraform
    expects.

    Args:
        config_path (str):  Path to user configs yaml file
        accounts_json_path (str): Path to output accounts.json file for use with
            Terraform.

    """
    tuc = load_terraform_user_config(config_path)

    email_prefix, email_domain = split_email(tuc.base_email)
    accounts = []
    for p in tuc.projects:
        accounts.append(
            {
                "name": p,
                "email": f"{email_prefix}+{p}@{email_domain}",
            }
        )
    accounts_config = {"accounts": accounts}
    with open(accounts_json_path, "w") as f:
        json.dump(accounts_config, f, indent=4)


def get_accounts_info(accounts_output_path: str) -> AccountsList:
    """Fetches account information, assuming terraform `create_accounts` configs have
    already been applied.

    Args:
        accounts_output_path (str): Path to Terraform output JSON file generated from
            managing accounts

    Returns:
        (List[Account]): List of instantiated Account models
    """
    quiet_dict = quiet_terraform_output_json(accounts_output_path)
    accounts_info = rearrange_quiet_terraform_output_dict(quiet_dict)
    accounts = []
    for name, info in accounts_info.items():
        info["name"] = name
        accounts.append(Account(**info))

    return AccountsList(accounts=accounts)


def generate_initial_iam_inputs(
    config_path: str, accounts_output_path: str, initial_iam_json_path: str
) -> None:
    accounts = get_accounts_info(accounts_output_path)
    tuc = load_terraform_user_config(config_path)

    # Update group_accounts by replacing account names with account IDs
    new_dict = {}
    for group, group_accounts in tuc.group_accounts.items():
        new_dict[group] = []
        for acc_name in group_accounts:
            acc_id = accounts.get_account_id(acc_name)
            new_dict[group].append(acc_id)

    tuc.group_accounts = new_dict

    # Write IAM config in format expected by Terraform
    iam_config = {}
    iam_config["groups"] = tuc.groups
    iam_config["group_accounts"] = tuc.group_accounts
    iam_config["users"] = []
    for user in tuc.unclass_users + tuc.secret_users:
        user_info = user.model_dump()
        iam_config["users"].append(user_info)

    iam_config["group_policy_arns"] = {
        "unclass_admin": ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }
    with open(initial_iam_json_path, "w") as f:
        json.dump(iam_config, f, indent=4)


def generate_terrafrom_initial_iam_configs(
    config_path: str,
    initial_iam_terraform_dir: str,
    iam_module_path: str,
    overwrite: bool = False,
) -> None:

    tuc = load_terraform_user_config(config_path)
    if path.isdir(initial_iam_terraform_dir):
        if overwrite:
            rmdir(initial_iam_terraform_dir)
    else:
        makedirs(initial_iam_terraform_dir)

    environment = Environment(loader=FileSystemLoader(TEMPLATES_DIR))

    # Get relative path from `iam_root_path` to `iam_module_path` b/c Terraform
    # does not allow absolute paths to sources in module blocks
    rel_path = path.relpath(iam_module_path, initial_iam_terraform_dir)

    # Write main.tf file
    template = environment.get_template("iam_main_tf.txt")
    init_iam_params = InitIamParam(
        profile=tuc.aws_profiles.identity_center.profile,
        region=tuc.aws_profiles.identity_center.region,
        relative_module_path=rel_path,
    )
    content = template.render(init_iam=init_iam_params)
    init_iam_main_path = path.join(initial_iam_terraform_dir, "main.tf")
    with open(init_iam_main_path, "w", encoding="utf-8") as f:
        f.write(content)

    # Write variables.tf
    template = environment.get_template("iam_variables_tf.txt")
    content = template.render()
    init_iam_vars_path = path.join(initial_iam_terraform_dir, "variables.tf")
    with open(init_iam_vars_path, "w", encoding="utf-8") as f:
        f.write(content)

    # Write output.tf
    template = environment.get_template("iam_output_tf.txt")
    content = template.render()
    init_iam_out_path = path.join(initial_iam_terraform_dir, "output.tf")
    with open(init_iam_out_path, "w", encoding="utf-8") as f:
        f.write(content)
