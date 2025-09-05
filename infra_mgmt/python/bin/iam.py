import argparse

from ..src.config import (
    generate_initial_iam_inputs,
    generate_terrafrom_initial_iam_configs,
)


def main(
    local_terraform_user_config_path: str,
    accounts_output_path: str,
    iam_json_path: str,
    iam_terraform_dir: str,
    iam_module_path: str,
):
    """Generates an iam_users.json file in the terraform/.config dir that defines
    Terrform variables for provisioning AWS groups and users and their respective
    account associations, and, populates the Terraform/.bin/iam dir with Terraform
    config files.

    Args:
        local_terraform_user_config_path (str): Path to Terraform user configuration
            yaml file
        accounts_output_path (str): Path to Terraform accounts_output.json file.
        iam_json_path (str): Path to iam_users.json config file used with
            Terraform
        iam_terraform_dir (str): Path to root iam Terraform module directory
        iam_module_path (str): Path to iam Terraform (non-root) module
    """
    generate_initial_iam_inputs(
        config_path=local_terraform_user_config_path,
        accounts_output_path=accounts_output_path,
        initial_iam_json_path=iam_json_path,
    )
    generate_terrafrom_initial_iam_configs(
        config_path=local_terraform_user_config_path,
        initial_iam_terraform_dir=iam_terraform_dir,
        iam_module_path=iam_module_path,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generates iam root Terraform module and input variables."
    )
    parser.add_argument(
        "local_terraform_user_config_path",
        help="Path to Terraform user configuration yaml file",
    )
    parser.add_argument(
        "accounts_output_path",
        help="Path to Terraform generated accounts_output.json file",
    )
    parser.add_argument(
        "iam_json_path",
        help="Path to iam_users.json config file",
    )
    parser.add_argument(
        "iam_terraform_dir",
        help="Path to root iam Terraform module directory",
    )
    parser.add_argument(
        "iam_module_path",
        help="Path to iam Terraform (non-root) module",
    )

    args = parser.parse_args()
    main(
        args.local_terraform_user_config_path,
        args.accounts_output_path,
        args.iam_json_path,
        args.iam_terraform_dir,
        args.iam_module_path,
    )
