import json
from os import listdir, makedirs, path, rmdir
from typing import List, Tuple

import yaml
from jinja2 import Environment, FileSystemLoader

from .models import (
    Account,
    AccountServicesConfig,
    AccountsList,
    AccountVpcVpnOctets,
    CICDConfigModel,
    HeaderConfigModel,
    IamConfigModel,
    InitIamParam,
    TerraformUserConfig,
    TestWebAppConfigModel,
    VpcVpnHeaderConfigModel,
    VpnVpcConfigModel,
)
from .utils import quiet_terraform_output_json, rearrange_quiet_terraform_output_dict

CURR_DIR = path.dirname(path.abspath(__file__))
TEMPLATES_DIR = path.join(CURR_DIR, "..", "templates", "terraform")


class ConfigError(Exception):
    pass


def config_makedirs(dirpath: str, overwrite: bool) -> None:
    """Custom version of makedirs method to facilitate overwrites if/when necessary."""
    if path.isdir(dirpath):
        if overwrite:
            rmdir(dirpath)
            makedirs(dirpath)
    else:
        makedirs(dirpath)


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


def get_account_services_config_paths(
    account_services_config_dir: str,
) -> Tuple[List[str], List[str]]:
    """Returns a list of filenames and a corresponding list of their absolute filepaths
    based on what is found in the user-configurations/account-services directory.

    Args:
        account_services_config_dir (str): Absolute path to the
            user-configurations/account-services directory

    Returns:
        (Tuple[List[str], List[str]]): First list is just filenames, the second list
            is absolute filepaths in same sequential order.
    """
    acc_servs_filenames = listdir(account_services_config_dir)
    return acc_servs_filenames, [
        path.join(account_services_config_dir, x) for x in acc_servs_filenames
    ]


def get_configured_modules_by_account(account_services_config_dir: str) -> dict:
    """Returns a dictionary of filepath: list of named services, used in later cross-
    validation checks.

    Args:
        account_services_config_dir (str): Absolute path to the
            user-configurations/account-services directory

    Returns:
        (dict): Each key is an absolute filepath to an account-services config file,
            each key is mapped to a list of services defined in that file.
    """
    _, filepaths = get_account_services_config_paths(account_services_config_dir)
    data = {}
    for fp in filepaths:
        config = yaml.safe_load(open(fp, "r"))
        data[fp] = list(config.keys())
    return data


def validate_account_names(
    account_services_config_dir: str, header_config: HeaderConfigModel
) -> None:
    """Validates account names encoded in account-services filenames match those found
    in the head.yaml user config file.

    Args:
        account_services_config_dir (str): Absolute path to the
            user-configurations/account-services directory
        header_config (HeaderConfigModel): Instantiated header configuration model from
            user configuration header.yaml file.

    Returns:
        None

    Raises:
        ConfigError: If account names do not match.
    """
    filenames, _ = get_account_services_config_paths(account_services_config_dir)
    for fname in filenames:
        account_name = fname.split(".services.yaml")[0]
        if account_name not in header_config.managed_accounts:
            msg = f"No account named {account_name} found in header.yaml config"
            raise ConfigError(msg)


def validate_account_services_modules(
    account_services_config_dir: str, modules_dir: str
) -> None:
    """Validates services included in all account-services config file against those
    defined in the Terraform modules dir.

    Args:
        account_services_config_dir (str): Absolute path to the
            user-configurations/account-services directory
        modules_dir (str): Absolute path to Terraform modules directory

    Returns:
        None

    Raises:
        ConfigError: If services in configs don't match those found in Terraform modules
            directory.
    """
    configs = get_configured_modules_by_account(account_services_config_dir)
    modules = listdir(modules_dir)
    invalid = {}
    for filepath, config_models in configs.items():
        for cm in config_models:
            if "ignore" in cm:
                continue
            if cm not in modules:
                if filepath not in invalid.keys():
                    invalid[filepath] = []
                invalid[filepath].append(cm)

    if len(invalid.keys()) > 0:
        msg = "Invalid module(s) defined in account-services configs.\n"
        msg += "The following listed modules, listed under their config\n"
        msg += "filepath, do not exist:\n"
        for fp in invalid.keys():
            msg += f"\t{fp}: {', '.join(invalid[fp])}\n"
        raise ConfigError(msg)


def validate_account_services(
    account_services_config_dir: str, header_config: HeaderConfigModel, modules_dir: str
) -> None:
    validate_account_names(account_services_config_dir, header_config)
    validate_account_services_modules(account_services_config_dir, modules_dir)


def form_account_services_config(
    account_services_config_dir: str,
    header_config: HeaderConfigModel,
    modules_dir: str,
    vpc_vpn_head_config: VpcVpnHeaderConfigModel,
) -> List[AccountServicesConfig]:
    """Forms the `account_services` attribute of the `TerraformUserConfig` model.

    Args:
        account_services_config_dir (str): Absolute path to the
            user-configurations/account-services directory
        header_config (HeaderConfigModel): Instantiated header configuration model from
            user configuration header.yaml file.
        modules_dir (str): Absolute path to Terraform modules directory
        vpc_vpn_head_config (VpcVpnHeaderConfigModel): Instantiated VPC-VPN config
            model from user configuration vpc-vpn-header.yaml file.

    Returns:
        (List[AccountServicesConfig]): `account_services` attribute of the
            `TerraformUserConfig` model
    """
    validate_account_services(account_services_config_dir, header_config, modules_dir)

    fnames, fpaths = get_account_services_config_paths(account_services_config_dir)

    acc_serv_config = []
    for idx, fname in enumerate(fnames):
        acc_config = yaml.safe_load(open(fpaths[idx], "r"))
        acc_name = fname.split(".services.yaml")[0]
        services = []
        for service in acc_config.keys():
            if "ignore" in service:
                continue
            if service == "cicd":
                services.append(CICDConfigModel(**acc_config[service]))
            if service == "vpc-vpn":
                acc_octets = AccountVpcVpnOctets(
                    **acc_config[service]["account-octets"]
                )
                services.append(
                    vpc_vpn_head_config.get_project_cidr_blocks(acc_octets=acc_octets)
                )
            if service == "test-webapp":
                services.append(TestWebAppConfigModel())
        acc_serv_config.append(
            AccountServicesConfig(account_name=acc_name, services=services)
        )
    return acc_serv_config


def validate_unique_vpc_vpn_octet_assigments(tuc: TerraformUserConfig) -> None:
    """Cross-check for overlapping VPC/VPN octets (should not be any).

    Args:
        tuc (TerraformUserConfig): Instantiated `TerraformUserConfig` model

    Returns:
        None

    Raises:
        ConfigError: If there are overlapping VPC/VPN octets.
    """
    vpc_configs_list = []
    for acc_serv in tuc.account_services:
        for service in acc_serv.services:
            if isinstance(service, VpnVpcConfigModel):
                vpc_configs_list.append(service.octets)
    if len(vpc_configs_list) > 1:
        all_non_client_octets = []
        all_client_octets = []
        for octets in vpc_configs_list:
            all_non_client_octets.append(octets.vpc_and_subnet)
            all_client_octets.append(octets.client)

            num_non_client_octets = len(all_non_client_octets)
            num_client_octets = len(all_client_octets)

            non_client_octet_set = set(all_non_client_octets)
            if len(non_client_octet_set) < num_non_client_octets:
                raise ConfigError(
                    "Non-unique non-client octet numbering found. Project octets must "
                    "be unique to avoid overlapping VPC/VPN CIDR blocks."
                )

            client_octet_set = set(all_client_octets)
            if len(client_octet_set) < num_client_octets:
                raise ConfigError(
                    "Non-unique client octet numbering found. Project octets must be "
                    "unique to avoid overlapping VPC/VPN CIDR blocks."
                )


def validate_iam(tuc: TerraformUserConfig, iam: IamConfigModel) -> None:
    """Cross-checks IAM user configurations.

    Ensures:
        1. Group names in group <> accounts map match those in groups list
        2. Account names in group <> accounts map match those listed in header.yaml
        3. Group names assigned to users match those in groups list

    Args:
        tuc (TerraformUserConfig): Instantiated `TerraformUserConfig` model
        iam (IamConfigModel): Instantiated `IamConfigModel` model

    Returns:
        None

    Raises:
        ConfigError: If any of the three checks fail.
    """

    # 1. Group names in group <> accounts map match those in groups list
    group_names = iam.groups
    for group in iam.group_accounts.keys():
        if group not in group_names:
            raise ConfigError(
                f"Group {group} in group <> accounts map does not exist in main groups"
                " list."
            )

    # 2. Account names in group <> accounts map match those listed in header.yaml
    header_acc_names = list(tuc.header.managed_accounts.keys())
    for group, group_accounts in iam.group_accounts.items():
        for acc in group_accounts:
            if acc not in header_acc_names:
                raise ConfigError(
                    f"Account {acc} for group {group} not in managed-accounts list. "
                    f"Expecting one of {', '.join(header_acc_names)}"
                )

    # 3. Group names assigned to users match those in groups list
    for user in iam.users:
        for group in user.groups:
            if group not in group_names:
                raise ConfigError(
                    f"Group {group} assigned to user {user.display_name} does not "
                    "exist in group list."
                )


def load_terraform_user_config(
    config_dir_path: str, tf_modules_dir: str
) -> TerraformUserConfig:
    """Loads the `TerraformUserConfig` model for later use in configuration processes.

    Args:
        config_dir_path (str): Absolute path to user-configurations directory
        tf_modules_dir (str): Absolute path to Terraform modules directory

    Returns:
        (TerraformUserConfig): Instantiated `TerraformUserConfig` model
    """
    header_path = path.join(config_dir_path, "header.yaml")
    iam_path = path.join(config_dir_path, "iam.yaml")
    vpc_header_path = path.join(config_dir_path, "vpc-vpn-header.yaml")
    acc_serv_dir = path.join(config_dir_path, "account-services")

    head = HeaderConfigModel(**yaml.safe_load(open(header_path, "r")))

    iam = IamConfigModel(**yaml.safe_load(open(iam_path, "r")))
    vpc_vpn_head = VpcVpnHeaderConfigModel(**yaml.safe_load(open(vpc_header_path, "r")))

    acc_servs = form_account_services_config(
        account_services_config_dir=acc_serv_dir,
        header_config=head,
        modules_dir=tf_modules_dir,
        vpc_vpn_head_config=vpc_vpn_head,
    )
    tuc = TerraformUserConfig(
        header=head, iam=iam, vpc_header=vpc_vpn_head, account_services=acc_servs
    )

    validate_iam(tuc, iam)
    validate_unique_vpc_vpn_octet_assigments(tuc)

    return tuc


def generate_org_accounts_config(
    config_dir_path: str,
    tf_modules_dir: str,
    org_json_path: str,
    tf_org_dir: str,
):
    """Generates an accounts configuration dictionary in a format that Terraform
    expects.

    Args:
        config_dir_path (str): Absolute path to user-configurations directory
        tf_modules_dir (str): Absolute path to Terraform modules directory
        org_json_path (str): Path to org.json config file
        tf_org_dir (str): Path to Terraform org dir where a terraform.tfvars file will
            be rendered from template and stored

    """
    tuc = load_terraform_user_config(config_dir_path, tf_modules_dir)

    email_prefix, email_domain = split_email(tuc.header.base_email)
    accounts = []

    for p in tuc.header.managed_accounts:
        if tuc.header.managed_accounts[p]:
            if "email" in tuc.header.managed_accounts[p].keys():
                accounts.append(
                    {
                        "name": p,
                        "email": f"{tuc.header.managed_accounts[p]["email"]}",
                        "parent_id": f"{tuc.header.parent_id}",
                    }
                )
        else:
            accounts.append(
                {
                    "name": p,
                    "email": f"{email_prefix}+{p}@{email_domain}",
                    "parent_id": f"{tuc.header.parent_id}",
                }
            )
    accounts_config = {"accounts": accounts}
    with open(org_json_path, "w") as f:
        json.dump(accounts_config, f, indent=4)

    environment = Environment(loader=FileSystemLoader(path.join(TEMPLATES_DIR, "org")))
    template = environment.get_template("org_tf_vars.txt")
    content = template.render(
        aws_profile_name=tuc.header.aws_profiles.identity_center.profile,
        aws_region=tuc.header.aws_profiles.identity_center.region,
    )
    fname = path.join(tf_org_dir, "terraform.tfvars")
    with open(fname, "w", encoding="utf-8") as f:
        f.write(content)


def get_org_accounts_info(org_output_path: str) -> AccountsList:
    """Fetches account information, assuming terraform `create_accounts` configs have
    already been applied.

    Args:
        org_output_path (str): Path to Terraform org_output.json file.

    Returns:
        (List[Account]): List of instantiated Account models
    """
    quiet_dict = quiet_terraform_output_json(org_output_path)
    accounts_info = rearrange_quiet_terraform_output_dict(quiet_dict)
    accounts = []
    for name, info in accounts_info.items():
        info["name"] = name
        accounts.append(Account(**info))

    return AccountsList(accounts=accounts)


def generate_initial_iam_inputs(
    config_dir_path: str,
    tf_modules_dir: str,
    org_output_path: str,
    initial_iam_json_path: str,
) -> None:
    """Generates a JSON file populated with values used in the IAM terraform module.

    Args:
        config_dir_path (str): Absolute path to user-configurations directory
        tf_modules_dir (str): Absolute path to Terraform modules directory
        org_output_path (str): Path to Terraform org_output.json file.
        initial_iam_json_path (str): Path to JSON file populated with values used in
            the IAM terraform module

    Returns:
        None
    """
    accounts = get_org_accounts_info(org_output_path)
    tuc = load_terraform_user_config(
        config_dir_path=config_dir_path, tf_modules_dir=tf_modules_dir
    )

    # Update group_accounts by replacing account names with account IDs
    new_dict = {}
    for group, group_accounts in tuc.iam.group_accounts.items():
        new_dict[group] = []
        for acc_name in group_accounts:
            acc_id = accounts.get_account_id(acc_name)
            new_dict[group].append(acc_id)

    tuc.iam.group_accounts = new_dict

    # Write IAM config in format expected by Terraform
    iam_config = {}
    iam_config["groups"] = tuc.iam.groups
    iam_config["group_accounts"] = tuc.iam.group_accounts
    iam_config["users"] = []
    for user in tuc.iam.users:
        user_info = user.model_dump()
        iam_config["users"].append(user_info)

    iam_config["group_policy_arns"] = {}
    for group in tuc.iam.groups:
        lc_group_name = group.lower()
        if "admin" in lc_group_name:
            iam_config["group_policy_arns"][group] = [
                "arn:aws:iam::aws:policy/AdministratorAccess"
            ]

    for group in tuc.iam.groups:
        if "developer" in group.lower():
            iam_config["group_policy_arns"][group] = [
                "arn:aws:iam::aws:policy/AWSCodeArtifactReadOnlyAccess"
            ]
    with open(initial_iam_json_path, "w") as f:
        json.dump(iam_config, f, indent=4)


def generate_terrafrom_initial_iam_configs(
    config_dir_path: str,
    tf_modules_dir: str,
    initial_iam_terraform_dir: str,
    iam_module_path: str,
) -> None:
    """Generates a JSON file populated with values used in the IAM terraform module.

    Args:
        config_dir_path (str): Absolute path to user-configurations directory
        tf_modules_dir (str): Absolute path to Terraform modules directory
        initial_iam_terraform_dir (str): Path to IAM Terraform (build) directory
        iam_module_path (str): Path to IAM Terraform (sub-) module

    Returns:
        None
    """

    tuc = load_terraform_user_config(
        config_dir_path=config_dir_path, tf_modules_dir=tf_modules_dir
    )

    environment = Environment(loader=FileSystemLoader(path.join(TEMPLATES_DIR, "iam")))

    # Get relative path from `iam_root_path` to `iam_module_path` b/c Terraform
    # does not allow absolute paths to sources in module blocks
    rel_path = path.relpath(iam_module_path, initial_iam_terraform_dir)

    # Write main.tf file
    template = environment.get_template("iam_main_tf.txt")
    init_iam_params = InitIamParam(
        profile=tuc.header.aws_profiles.identity_center.profile,
        region=tuc.header.aws_profiles.identity_center.region,
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


def get_review_build_emails_in_account(
    iam_inputs_path: str, account: Account
) -> List[str]:
    """Fetches a list of user emails to be added to 'reviewer' subscription list.

    Args:
        iam_inputs_path (str): JSON file generated by the `generate_initial_iam_inputs`
            method
        account (Account): An `Account` object pulled from the JSON file generated by
            the `get_org_accounts_info` method

    Returns:
        (List[str]): List of email addresses
    """
    emails = []
    iam_input = json.load(open(iam_inputs_path, "r"))
    for user in iam_input["users"]:
        for group in user["groups"]:
            if "developer" in group.lower() or "admin" in group.lower():

                emails.append(user["email"])
    emails = list(set(emails))
    return emails


def generate_individual_terraform_account_modules(
    config_dir_path: str,
    tf_modules_dir: str,
    org_output_path: str,
    accounts_tf_build_dir: str,
    iam_inputs_path: str,
    overwrite: bool = False,
) -> None:
    """Generates individual root Terraform modules for each AWS account managed by the
    Organization's management account.

    Args:
        config_dir_path (str): Absolute path to user-configurations directory
        tf_modules_dir (str): Absolute path to Terraform modules directory
        org_output_path (str): Path to Terraform org_output.json file.
        accounts_tf_build_dir (str): Path to Terraform build accounts directory
        iam_inputs_path (str): JSON file generated by the `generate_initial_iam_inputs`
            method
        overwrite (bool, default=False): Determines whether to overwrite a folder
            upon creation if one of the same name already exists.

    Returns:
        None
    """
    tuc = load_terraform_user_config(
        config_dir_path=config_dir_path, tf_modules_dir=tf_modules_dir
    )

    accounts = get_org_accounts_info(org_output_path)
    environment = Environment(
        loader=FileSystemLoader(path.join(TEMPLATES_DIR, "accounts"))
    )
    for acc in accounts.accounts:

        # Create account module path and ensure directory exists
        acc_module_path = path.join(accounts_tf_build_dir, acc.name)
        config_makedirs(acc_module_path, overwrite)

        # --- Main Configs (main.tf, variables.tf, etc.) ---
        cicd = False
        git_type = None
        github = None
        vpc = False
        test_webapp = False
        services = tuc.get_services_for_account(acc.name)
        for service in services:
            if isinstance(service, CICDConfigModel):
                cicd = True
                git_type = service.git
                if git_type == "GitHub":
                    github = service.github
            if isinstance(service, VpnVpcConfigModel):
                vpc = True
                vpc_config = service
            if isinstance(service, TestWebAppConfigModel):
                test_webapp = True

        # Write main.tf file
        template = environment.get_template("account_main_tf.txt")
        content = template.render(
            org_main_region=tuc.header.aws_profiles.org_main.region,
            org_main_profile=tuc.header.aws_profiles.org_main.profile,
            id_center_region=tuc.header.aws_profiles.identity_center.region,
            id_center_profile=tuc.header.aws_profiles.identity_center.profile,
            cicd=cicd,
            git_type=git_type,
            vpc=vpc,
            test_webapp=test_webapp,
        )
        acc_main_path = path.join(acc_module_path, "main.tf")
        with open(acc_main_path, "w", encoding="utf-8") as f:
            f.write(content)

        # Write variables.tf
        template = environment.get_template("account_variables_tf.txt")
        content = template.render(
            cicd=cicd,
            git_type=git_type,
            vpc=vpc,
            test_webapp=test_webapp,
        )
        acc_vars_path = path.join(acc_module_path, "variables.tf")
        with open(acc_vars_path, "w", encoding="utf-8") as f:
            f.write(content)

        # Write output.tf
        template = environment.get_template("account_output_tf.txt")
        content = template.render(
            cicd=cicd,
            git_type=git_type,
            vpc=vpc,
            test_webapp=test_webapp,
        )
        acc_out_path = path.join(acc_module_path, "output.tf")
        with open(acc_out_path, "w", encoding="utf-8") as f:
            f.write(content)

        # --- TFVARS File ---
        target_accound_id = acc.account_ids
        s3_git_bucket_name = f"{tuc.header.org_prefix}-{acc.name.lower()}-s3-git-bucket"
        codeartifact_domain_name = (
            f"{tuc.header.org_prefix}-{acc.name.lower()}-ca-domain-1"
        )
        codeartifact_repository_name = (
            f"{tuc.header.org_prefix}-{acc.name.lower()}-ca-repo-1"
        )
        codebuild_project_name = f"{tuc.header.org_prefix}-{acc.name.lower()}-build-1"
        emails = get_review_build_emails_in_account(
            iam_inputs_path=iam_inputs_path, account=acc
        )

        # account_cidr_blocks = tuc.vpn_vpc.get_project_cidr_blocks(acc.name)

        template = environment.get_template("account_tfvars.txt")
        content = template.render(
            target_accound_id=target_accound_id,
            s3_git_bucket_name=s3_git_bucket_name,
            review_notification_emails=emails,
            build_notification_emails=emails,
            codeartifact_domain_name=codeartifact_domain_name,
            codeartifact_repository_name=codeartifact_repository_name,
            codebuild_project_name=codebuild_project_name,
            vpc_cidr_block=vpc_config.vpc_cidr_block if vpc else None,
            subnet_cidr_block=vpc_config.subnet_cidr_block if vpc else None,
            public_subnet_cidr_block=(
                vpc_config.public_subnet_cidr_block if vpc else None
            ),
            client_vpn_endpoint_client_cidr_block=(
                vpc_config.client_cidr if vpc else None
            ),
            cert_common_name=tuc.vpc_header.server_certificate.common_name,
            cert_organization=tuc.vpc_header.server_certificate.organization,
            account_alias=acc.name,
            cicd=cicd,
            git_type=git_type,
            github=github,
            vpc=vpc,
            test_webapp=test_webapp,
        )
        acc_tfvars_path = path.join(acc_module_path, "terraform.tfvars")
        with open(acc_tfvars_path, "w", encoding="utf-8") as f:
            f.write(content)

        # --- VPN Client Certificate Generation ---
        # Find all users who have access to this account and have vpn_access enabled
        if vpc:
            vpn_users = []
            all_users = tuc.iam.users
            for user in all_users:
                if not user.vpn_access:
                    continue

                # Check if any of the user's groups grant access to the current account
                for group_name in user.groups:
                    if acc.name in tuc.iam.group_accounts.get(group_name, []):
                        vpn_users.append(user)
                        break  # User is added, no need to check other groups

            # Write vpn_clients.tf file
            if vpn_users:
                template = environment.get_template("account_vpn_clients_tf.txt")
                content = template.render(
                    vpn_users=vpn_users,
                    account_alias=acc.name,
                )
                acc_vpn_clients_path = path.join(acc_module_path, "vpn_clients.tf")
                with open(acc_vpn_clients_path, "w", encoding="utf-8") as f:
                    f.write(content)
