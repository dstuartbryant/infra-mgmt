import argparse

from ..src.config import generate_individual_org_terraform_account_modules


def main(
    local_terraform_user_config_path: str,
    accounts_output_path: str,
    iam_json_path: str,
    org_terraform_dir: str,
) -> None:
    """Generates an terraform module for individual organization accounts.

    Args:
        local_terraform_user_config_path (str): Path to Terraform user configuration
            yaml file
        accounts_output_path (str): Path to Terraform accounts_output.json file.
        iam_json_path (str): Path to iam_users.json config file used with
            Terraform
        org_terraform_dir (str): Parent directory where each account's module will
            be written.
    """
    generate_individual_org_terraform_account_modules(
        config_path=local_terraform_user_config_path,
        accounts_output_path=accounts_output_path,
        iam_inputs_path=iam_json_path,
        org_terraform_dir=org_terraform_dir,
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
        "org_terraform_dir",
        help="Path to parent directory where each account's module will be written.",
    )

    args = parser.parse_args()
    main(
        args.local_terraform_user_config_path,
        args.accounts_output_path,
        args.iam_json_path,
        args.org_terraform_dir,
    )
