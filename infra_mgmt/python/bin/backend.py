import argparse
from os import path

from jinja2 import Environment, FileSystemLoader

from ..src.config import load_terraform_user_config

CURR_DIR = path.dirname(path.abspath(__file__))
PYTHON_DIR = path.dirname(path.abspath(CURR_DIR))
SRC_DIR = path.join(PYTHON_DIR, "src")
TEMPLATES_DIR = path.join(SRC_DIR, "templates", "backend")


def main(
    local_terraform_user_config_dir_path: str,
    terraform_modules_dir: str,
    backend_terraform_dir: str,
):
    """Generates a terraform.tfvars file in the terraform/backend dir that defines
    Terrform variables

    Args:
        local_terraform_user_config_dir_path (str): Path to Terraform user configuration
            directory.
        terraform_modules_dir (str): Path to Terraform module directory
        backend_terraform_dir (str): Path to backend Terrform dir
    """
    tuc = load_terraform_user_config(
        config_dir_path=local_terraform_user_config_dir_path,
        tf_modules_dir=terraform_modules_dir,
    )

    environment = Environment(loader=FileSystemLoader(TEMPLATES_DIR))
    template = environment.get_template("backend_tfvars.txt")
    content = template.render(
        profile=tuc.header.aws_profiles.backend.profile,
        region=tuc.header.aws_profiles.backend.region,
        bucket_name=tuc.header.backend.bucket_name,
        table_name=tuc.header.backend.dynamodb_table_name,
    )
    output_path = path.join(backend_terraform_dir, "terraform.tfvars")
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate terraform.tfvars for backend"
    )
    parser.add_argument(
        "local_terraform_user_config_dir_path",
        help="Path to Terraform user configuration directory",
    )
    parser.add_argument(
        "terraform_modules_dir",
        help="Path to Terraform modules directory",
    )
    parser.add_argument("backend_terraform_dir", help="Path to backend Terraform dir")
    args = parser.parse_args()
    main(
        args.local_terraform_user_config_dir_path,
        args.terraform_modules_dir,
        args.backend_terraform_dir,
    )
