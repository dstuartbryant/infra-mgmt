import json
from os import listdir, makedirs, path
from typing import List, Tuple

import yaml
from jinja2 import Environment, FileSystemLoader

from .new_models import Account, AccountsList, TerraformUserConfig
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
):
    accounts = get_accounts_info(accounts_output_path)
    tuc = load_terraform_user_config(config_path)

    # Update group_accounts by replacing account names with account IDs
    # new_dict_list = []
    # for grp_acc in tuc.group_accounts:
    #     new_dict = {}
    #     group = list(grp_acc.keys())[0]
    #     new_dict[group] = []
    #     accs = list(grp_acc.values())[0]
    #     for acc_name in accs:
    #         acc_id = accounts.get_account_id(acc_name)
    #         new_dict[group].append(acc_id)
    #     new_dict_list.append(new_dict)
    # tuc.group_accounts = new_dict_list

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

    return tuc, accounts


def generate_terrafrom_initial_iam_configs(
    config_path: str,
    accounts_output_path: str,
    initial_iam_json_path: str,
    initial_iam_terraform_dir: str,
):
    pass
