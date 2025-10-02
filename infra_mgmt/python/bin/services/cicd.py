import argparse

from ...src.services.python_package.config import apply_all_cicd_services


def main(
    local_terraform_user_config_dir_path: str,
    terraform_modules_dir: str,
    account_tf_output_dir: str,
    package_build_dir: str,
):
    apply_all_cicd_services(
        config_dir_path=local_terraform_user_config_dir_path,
        tf_modules_dir=terraform_modules_dir,
        acc_tf_output_dir=account_tf_output_dir,
        package_build_dir=package_build_dir,
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
    parser.add_argument(
        "account_tf_output_dir",
        help="Path to Terraform output directory",
    )
    parser.add_argument(
        "package_build_dir", help="Path to directory where packages are built"
    )

    args = parser.parse_args()
    main(
        args.local_terraform_user_config_dir_path,
        args.terraform_modules_dir,
        args.account_tf_output_dir,
        args.package_build_dir,
    )
