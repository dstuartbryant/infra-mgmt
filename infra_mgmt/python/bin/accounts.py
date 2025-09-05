import argparse

from ..src.config import generate_accounts_config


def main(local_terraform_user_config_path: str, accounts_json_path: str):
    """Generates an accounts.json file in the terraform/.config dir that defines
    Terrform variables for provisioning AWS accounts.

    Args:
        local_terraform_user_config_path (str): Path to Terraform user configuration
            yaml file
        accounts_json_path (str): Path to accounts.json config file.
    """
    generate_accounts_config(
        config_path=local_terraform_user_config_path,
        accounts_json_path=accounts_json_path,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generates an accounts.json file for provisioning AWS accounts"
    )
    parser.add_argument(
        "local_terraform_user_config_path",
        help="Path to Terraform user configuration yaml file",
    )
    parser.add_argument("accounts_json_path", help="Path to accounts.json config file")
    args = parser.parse_args()
    main(args.local_terraform_user_config_path, args.accounts_json_path)
