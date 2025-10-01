"""Services configuration module.


Steps for applying Git Repos/Package Artifacts
----------------------------------------------
For each AccountServicesConfig in tuc.account_services:
1. Get account CICD metadata; `get_account_cicd_metadata`
2. Get a list of folders in the CICD pipeline's Git S3 bucket
3. Get a list of Package Names from pipeline's CodeArtifact repo

RULE 1: If `<git-repo-A>` is a folder in S3 bucket, but there is no `<git-repo-A>`
    package (or similar naming) in CodeArtifact repo:

    Assume that a developer has created a new repo and not run CICD yet to publish
    their package yet.

    WHY?: Because this could happen, so, we'll not attempt to do any "restarts" in
        initializing repos/packages. We'll have to manually groom the pipelines for now

4. For each package defined in account's services.yaml file:
    4.1: If package name exists in (or maps to) an folder in the Git S3 Bucket
        - Continue
    4.2: Otherwise, populate template inputs
    4.3: Create a new dir (real or temp)
    4.4: Render and write templates (adhering to struture) to new dir
    4.5: Then what?--|
                     |
 |--------------------
 |
Need to run:

# - eval $(poetry env activate) or maybe poetry install
# - git init
- git remote add origin s3://git-s3-bucket-name
- git add
- git commit -m "init commit"
- git push --set-upstream origin main


But if developer wants to download dev-continer zip, what do they do?


"""

import json
import os
import shutil
import subprocess
from os import listdir, makedirs, path
from pathlib import Path

from jinja2 import Environment, FileSystemLoader

from .aws import get_boto3_session, list_codeartifact_packages, list_s3_folders
from .models import CicdMetadata, PythonPackageInput

CURR_DIR = path.dirname(path.abspath(__file__))  # python_packages dir
TEMPLATES_DIR = path.join(
    CURR_DIR, "..", "..", "templates", "services", "cicd", "packages", "python"
)


def get_account_cicd_metadata(
    account_name: str, acc_tf_output_dir: str
) -> CicdMetadata:
    acc_tf_output_path = path.join(acc_tf_output_dir, account_name)
    acc_output = json.load(open(acc_tf_output_path, "r"))
    return CicdMetadata(
        codeartifact_domain=acc_output["codeartifact_domain_name"]["value"],
        codeartifact_domain_owner=acc_output["target_account_id"]["value"],
        codeartifact_repo=acc_output["codeartifact_repository_name"]["value"],
        codeartifact_region=acc_output["codeartifact_region"]["value"]["name"],
        git_s3_bucket=acc_output["s3_git_bucket_name"]["value"],
    )


def list_git_and_codeartifact_repos(cicd_meta: CicdMetadata, profile: str):
    s3_folders = list_s3_folders(
        profile=profile,
        region=cicd_meta.codeartifact_region,
        bucket_name=cicd_meta.git_s3_bucket,
        account_id_to_assume=cicd_meta.codeartifact_domain_owner,
    )

    ca_packs = list_codeartifact_packages(
        profile=profile,
        region=cicd_meta.codeartifact_region,
        domain=cicd_meta.codeartifact_domain,
        repository=cicd_meta.codeartifact_repo,
        account_id_to_assume=cicd_meta.codeartifact_domain_owner,
    )
    return s3_folders, ca_packs


def populate_python_package_contents(
    template_input: PythonPackageInput, package_destination_folder_path: str
):
    # Create folder structure
    dev_container_dir = path.join(
        package_destination_folder_path, f"{template_input.package_name}-dev-container"
    )
    dot_dev_container_dir = path.join(dev_container_dir, ".devcontainer")
    zsh_dir = path.join(dev_container_dir, "zsh")
    src_dir = path.join(package_destination_folder_path, "src")
    tests_dir = path.join(package_destination_folder_path, "tests")

    dirs_to_create = [
        package_destination_folder_path,
        dot_dev_container_dir,
        dot_dev_container_dir,
        zsh_dir,
        src_dir,
        tests_dir,
    ]
    for dir_path in dirs_to_create:
        makedirs(name=dir_path, exist_ok=True)

    # Render templates
    environment = Environment(loader=FileSystemLoader(path.join(TEMPLATES_DIR)))
    template_filenames = [x for x in listdir(TEMPLATES_DIR) if ".jinja2" in x]
    for tf in template_filenames:
        template = environment.get_template(tf)
        content = template.render(config=template_input)
        content_filename = tf.replace(".jinja2", "")
        if content_filename in [".env", "compose.yaml", "Dockerfile", "post-start.sh"]:
            content_dir = dev_container_dir
        elif content_filename in ["devcontainer.json"]:
            content_dir = dot_dev_container_dir
        else:
            content_dir = package_destination_folder_path

        content_file_path = path.join(content_dir, content_filename)
        with open(content_file_path, "w", encoding="utf-8") as f:
            f.write(content)

    # Copy over ZSH files
    template_zsh_dir = path.join(TEMPLATES_DIR, "zsh")
    zsh_filenames = listdir(template_zsh_dir)
    for zfn in zsh_filenames:
        source_path = path.join(template_zsh_dir, zfn)
        destination_path = path.join(zsh_dir, zfn)
        shutil.copyfile(src=source_path, dst=destination_path)

    # Populate temporary Python scripts
    # - src
    module_path = path.join(src_dir, template_input.docker_compose_service_name)
    makedirs(module_path)
    Path(path.join(module_path, "__init__.py")).touch()
    template = environment.get_template("src.core")
    content = template.render(config=template_input)
    core_fpath = path.join(module_path, "core.py")
    with open(core_fpath, "w", encoding="utf-8") as f:
        f.write(content)
    # - tests
    Path(path.join(tests_dir, "__init__.py")).touch()
    template = environment.get_template("test.core")
    content = template.render(config=template_input)
    test_core_fpath = path.join(tests_dir, "test_core.py")
    with open(test_core_fpath, "w", encoding="utf-8") as f:
        f.write(content)


def initialize_and_push_git_repository(
    directory_path: str,
    s3_bucket_with_key: str,
    commit_message: str,
    aws_profile: str,
    aws_region: str,
    aws_account_id_to_assume: str,
    aws_role_to_assume: str = "OrganizationAccountAccessRole",
):
    """
    Initializes a Git repository, adds an S3 remote, commits, and pushes the initial
    content using dynamically assumed AWS credentials.

    Args:
        directory_path: The path to the directory to be initialized as a Git repository.
        s3_bucket_with_key: The name of the S3 bucket including repo key.
        commit_message: The commit message for the initial commit.
        aws_profile: The source AWS profile for assuming the role.
        aws_region: The AWS region for the session.
        aws_account_id_to_assume: The target AWS account ID.
        aws_role_to_assume: The role to assume in the target account.
    """
    print("Attempting to get temporary credentials...")
    session = get_boto3_session(
        profile=aws_profile,
        region=aws_region,
        account_id_to_assume=aws_account_id_to_assume,
        role_name_to_assume=aws_role_to_assume,
    )
    if not session:
        print("Failed to create boto3 session. Aborting.")
        return

    credentials = session.get_credentials()
    if not credentials:
        print("Failed to get temporary credentials. Aborting.")
        return

    print("Successfully obtained temporary credentials.")

    # Set up the environment for the subprocess with temporary credentials
    env = os.environ.copy()
    env["AWS_ACCESS_KEY_ID"] = credentials.access_key
    env["AWS_SECRET_ACCESS_KEY"] = credentials.secret_key
    env["AWS_SESSION_TOKEN"] = credentials.token
    env["AWS_REGION"] = aws_region
    # Unset profile to ensure credentials are used
    if "AWS_PROFILE" in env:
        del env["AWS_PROFILE"]

    s3_remote_url = f"s3://{s3_bucket_with_key}"
    print(f"Using S3 remote URL: {s3_remote_url}")

    commands = [
        ("poetry", "install"),
        ("poetry", "run", "black", "./src", "./tests"),
        ("git", "init"),
        ("git", "branch", "-m", "main"),
        ("git", "remote", "add", "origin", s3_remote_url),
        ("git", "add", "."),
        ("git", "commit", "-m", commit_message),
        ("git", "push", "--set-upstream", "origin", "main"),
    ]

    for command in commands:
        try:
            result = subprocess.run(
                command,
                check=True,
                capture_output=True,
                text=True,
                cwd=directory_path,
                env=env,
            )
            print(f"Successfully executed: {' '.join(command)}")
            if result.stdout:
                print(result.stdout)
        except subprocess.CalledProcessError as e:
            print(f"Error executing: {' '.join(command)}")
            print(f"Return code: {e.returncode}")
            if e.stderr:
                print(f"Stderr:\n{e.stderr}")
            if e.stdout:
                print(f"Stdout:\n{e.stdout}")
            return
        except FileNotFoundError:
            print(
                f"Error: '{command[0]}' command not found. Is it installed and in your"
                " PATH?"
            )
            return
