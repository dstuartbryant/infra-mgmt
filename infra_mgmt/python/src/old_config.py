"""Configuration module."""

import json
from os import listdir, makedirs, path
from typing import List, Tuple

import yaml
from jinja2 import Environment, FileSystemLoader

from .old_models import AccessConfig, Account, Project, Projects
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


def get_access_config_filepaths(configs_dir: str) -> List[str]:
    """Finds access config files in user configs dir and returns their absolute
    filepaths.

    Args:
        configs_dir (str): Path to user configs dir.
    """
    fnames = listdir(configs_dir)
    access_fnames = [x for x in fnames if "access." in x]
    return [path.join(configs_dir, x) for x in access_fnames]


def load_configs(configs_dir: str) -> Tuple[Projects, List[AccessConfig]]:
    """Loads user config files and performs cross check validations.
    Args:
        configs_dir (str): Path to user configs dir.

    Returns:
        (Projects): Instantiated projects model
        (List[AccessConfig]): List of instantiated AccessConfig models
    """
    projects_yml = path.join(configs_dir, "projects.yaml")
    access_ymls = get_access_config_filepaths(configs_dir)

    # Load projects config
    pconfig = yaml.safe_load(open(projects_yml, "r"))
    projects = Projects(
        base_email=pconfig["base_email"],
        projects=[Project(**x) for x in pconfig["projects"]],
    )

    access_configs = []
    for ay in access_ymls:
        classification = ay.split("access.")[-1].split(".yaml")[0]
        ac = AccessConfig(**yaml.safe_load(open(ay, "r")))
        for user in ac.users:
            for project in user.projects:
                configured_project = projects.get_project(project)
                if classification not in configured_project.classifications:
                    raise ConfigError(
                        f"Project {project} does not have a {classification} "
                        "classification. Possible classifications include: "
                        f"{", ".join(configured_project.classifications)}"
                    )
        access_configs.append(ac)

    return projects, access_configs


def generate_accounts_config(configs_dir: str, accounts_json_path: str) -> Projects:
    """Generates an accounts configuration dictionary in a format that Terraform
    expects.

    Args:
        configs_dir (str):  Path to user configs dir
        accounts_json_path (str): Path to output accounts.json file for use with
            Terraform.

    """
    projects, access_configs = load_configs(configs_dir)

    email_prefix, email_domain = split_email(projects.base_email)
    accounts = []
    for p in projects.projects:
        for classification in p.classifications:
            acc_name = f"{p.name}-{classification}"
            accounts.append(
                {
                    "name": acc_name,
                    "email": f"{email_prefix}+{acc_name}@{email_domain}",
                }
            )
    accounts_config = {"accounts": accounts}
    with open(accounts_json_path, "w") as f:
        json.dump(accounts_config, f, indent=4)

    return projects


def get_accounts_info(accounts_output_path: str) -> List[Account]:
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

    return accounts


def original_generate_terraform_org_configs(
    accounts_output_path: str, s3_prefix: str, org_terraform_dir: str
):
    """Generates a terraform providers file for use with organizational resource
    management across multiple AWS accounts.

    NOTE: Original draft of org terrform configs. Assumed only one "root" dir for
    all accounts.

    Args:
        accounts_output_path (str): Path to Terraform output JSON file generated from
            managing accounts
        s3_prefix (str): A prefix applied to Git remote S3 bucket names to support
            universally unique bucket names
        org_terraform_dir (str): Destination folder where providers.tf and main.tf files
            will be written

    """
    quiet_dict = quiet_terraform_output_json(accounts_output_path)
    accounts_info = rearrange_quiet_terraform_output_dict(quiet_dict)
    accounts = []
    for name, info in accounts_info.items():
        info["name"] = name
        accounts.append(Account(**info))

    environment = Environment(loader=FileSystemLoader(TEMPLATES_DIR))

    template = environment.get_template("accounts_providers.txt")
    content = template.render(accounts=accounts, prefix=s3_prefix)

    providers_output_path = path.join(org_terraform_dir, "providers.tf")
    with open(providers_output_path, "w", encoding="utf-8") as f:
        f.write(content)

    template = environment.get_template("org_main_tf.txt")
    content = template.render(accounts=accounts, prefix=s3_prefix)

    main_output_path = path.join(org_terraform_dir, "main.tf")
    with open(main_output_path, "w", encoding="utf-8") as f:
        f.write(content)
    return accounts


def generate_terraform_org_configs(
    accounts_output_path: str,
    s3_prefix: str,
    build_dir: str,
    overwrite: bool = False,
):
    """Generates terraform organization configs.


    Args:
        accounts_output_path (str): Path to Terraform output JSON file generated from
            managing accounts
        s3_prefix (str): A prefix applied to Git remote S3 bucket names to support
            universally unique bucket names
        build_dir (str): Destination folder where providers.tf and main.tf files
            will be written
         overwrite (bool, default=False): Whether to overwrite any prexisting directory

    """

    # Fetch and format accounts meta data
    quiet_dict = quiet_terraform_output_json(accounts_output_path)
    accounts_info = rearrange_quiet_terraform_output_dict(quiet_dict)
    accounts = []
    for name, info in accounts_info.items():
        info["name"] = name
        accounts.append(Account(**info))

    # Ensure build dir exists/create one
    makedirs(build_dir, exist_ok=overwrite)

    for account in accounts:
        makedirs(path.join(build_dir, account.alias), exist_ok=overwrite)


# def generate_personnel_confgs()
