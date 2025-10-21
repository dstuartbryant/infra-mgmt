import argparse

from ...src.backup_reinit import generate_backup_archive


def main(
    local_terraform_user_config_dir_path: str,
    terraform_modules_dir: str,
) -> None:
    """Generates instantaneous project configurations backup .zip archive and uploads
    it to the AWS Organization's Management account's purpose-made S3 bucket.

    Args:
        local_terraform_user_config_dir_path (str): Path to the user configs directory.
        terraform_modules_dir (str): Path to the terraform modules directory.
    """

    generate_backup_archive(
        config_dir_path=local_terraform_user_config_dir_path,
        tf_modules_dir=terraform_modules_dir,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generates iam root Terraform module and input variables."
    )
    parser.add_argument(
        "local_terraform_user_config_dir_path",
        help="Path to Terraform user configuration directory",
    )
    parser.add_argument(
        "terraform_modules_dir",
        help="Path to Terraform modules directory",
    )

    args = parser.parse_args()
    main(
        args.local_terraform_user_config_dir_path,
        args.terraform_modules_dir,
    )
