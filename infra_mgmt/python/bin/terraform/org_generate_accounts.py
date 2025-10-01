import argparse

from ...src.terraform.config import generate_org_accounts_config


def main(
    local_terraform_user_config_dir_path: str,
    terraform_modules_dir: str,
    org_json_path: str,
    terraform_org_dir: str,
):
    """Generates an accounts.json file in the terraform/.config dir that defines
    Terrform variables for provisioning AWS accounts.

    Args:
        local_terraform_user_config_dir_path (str): Path to Terraform user configuration
            directory.
        terraform_modules_dir (str): Path to Terraform module directory
        org_json_path (str): Path to org.json config file
        terraform_org_dir (str): Path to Terraform org dir where a terraform.tfvars
            file will be rendered from template and stored
    """
    generate_org_accounts_config(
        config_dir_path=local_terraform_user_config_dir_path,
        tf_modules_dir=terraform_modules_dir,
        org_json_path=org_json_path,
        tf_org_dir=terraform_org_dir,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generates an accounts.json file for provisioning AWS accounts"
    )
    parser.add_argument(
        "local_terraform_user_config_dir_path",
        help="Path to Terraform user configuration directory",
    )
    parser.add_argument(
        "terraform_modules_dir",
        help="Path to Terraform modules directory",
    )
    parser.add_argument("org_json_path", help="Path to accounts.json config file")
    parser.add_argument(
        "terraform_org_dir",
        help="Path to Terraform org directory",
    )
    args = parser.parse_args()
    main(
        args.local_terraform_user_config_dir_path,
        args.terraform_modules_dir,
        args.org_json_path,
        args.terraform_org_dir,
    )
