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
    4.5: Initialize and push git repository


"""

import json
import os
import shutil
import subprocess
from os import listdir, makedirs, path
from pathlib import Path

from jinja2 import Environment, FileSystemLoader

from ...terraform.config import load_terraform_user_config
from ...terraform.models import CICDConfigModel
from .aws import get_boto3_session, list_codeartifact_packages, list_s3_folders
from .models import CicdMetadata, PythonPackageInput
from .utils import generate_pastel_hex

CURR_DIR = path.dirname(path.abspath(__file__))  # python_packages dir
TEMPLATES_DIR = path.join(
    CURR_DIR, "..", "..", "templates", "services", "cicd", "packages", "python"
)


def get_account_cicd_metadata(
    account_name: str, acc_tf_output_dir: str
) -> CicdMetadata:
    acc_tf_output_path = path.join(acc_tf_output_dir, account_name + ".json")
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
    pruned_s3_folders = []
    for f in s3_folders:
        if f[-1] == "/":
            pruned_s3_folders.append(f[:-1])
        else:
            pruned_s3_folders.append(f)

    ca_packs = list_codeartifact_packages(
        profile=profile,
        region=cicd_meta.codeartifact_region,
        domain=cicd_meta.codeartifact_domain,
        repository=cicd_meta.codeartifact_repo,
        account_id_to_assume=cicd_meta.codeartifact_domain_owner,
    )
    return pruned_s3_folders, ca_packs


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
        if content_filename in [
            ".env.template",
            "compose.yaml",
            "Dockerfile",
            "post-start.sh",
        ]:
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


def apply_account_cicd_services(
    ccm: CICDConfigModel,
    acc_name: str,
    acc_tf_output_dir: str,
    profile: str,
    organization_name: str,
    organization_email: str,
    package_build_dir: str,
):

    tf_cicd_meta = get_account_cicd_metadata(
        account_name=acc_name, acc_tf_output_dir=acc_tf_output_dir
    )

    curr_s3_folders, curr_ca_packs = list_git_and_codeartifact_repos(
        cicd_meta=tf_cicd_meta, profile=profile
    )

    # Generate preview/plan and check with user
    do_not_require_init = []
    require_init = []
    local_config_packs = []
    for pack in ccm.packages.python:
        local_config_packs.append(pack.name)
        if pack.name in curr_s3_folders:
            do_not_require_init.append(pack.name)
        else:
            require_init.append(pack.name)

    msg = f"\n\n\n----------------------- CICD Plan for Account: {acc_name} ---------"
    msg += "---------------\n"
    msg += "Current S3 Folders:\n"
    msg += "\n".join(curr_s3_folders) + "\n\n"

    msg += "Current CodeArtifact Packages:\n"
    msg += "\n".join(curr_ca_packs) + "\n\n"

    msg += "Packages in local config:\n"
    msg += "\n".join(local_config_packs) + "\n\n"

    msg += "DO NOT require initialization:\n"
    msg += "\n".join(do_not_require_init) + "\n\n"

    msg += "REQUIRE initialization:"
    if len(require_init) > 0:
        msg += "\n" + "\n".join(require_init) + "\n\n"
    else:
        msg += " None\n\n"

    print(msg)

    if len(require_init) == 0:
        print("\nNothing to change, skipping.\n")
    else:
        expected_input = "yes"
        user_input = input("Apply CICD plan? (only `yes` is accepted for continuing):")
        if user_input != expected_input:
            print("User declined plan application, stopping.")
        else:
            # Apply Plan
            for pack_name in require_init:
                print(f"Applying plan for package {pack_name}")
                pack = ccm.get_package_config(name=pack_name)
                hypen_pack_name = pack.name
                underscore_pack_name = pack.name.replace("-", "_")
                pack_build_dir = path.join(package_build_dir, underscore_pack_name)
                s3_bucket_with_key = f"{tf_cicd_meta.git_s3_bucket}/{hypen_pack_name}"
                makedirs(pack_build_dir)
                ppi = PythonPackageInput(
                    dev_container_name=f"{hypen_pack_name}-dev-container",
                    docker_compose_service_name=underscore_pack_name,
                    terminal_background_color=generate_pastel_hex(),
                    organization_name=organization_name,
                    organization_email=organization_email,
                    package_name=hypen_pack_name,
                    codeartifact=tf_cicd_meta,
                )
                populate_python_package_contents(
                    template_input=ppi, package_destination_folder_path=pack_build_dir
                )
                initialize_and_push_git_repository(
                    directory_path=pack_build_dir,
                    s3_bucket_with_key=s3_bucket_with_key,
                    commit_message="automated init commit",
                    aws_profile=profile,
                    aws_region=ppi.codeartifact.codeartifact_region,
                    aws_account_id_to_assume=ppi.codeartifact.codeartifact_domain_owner,
                )


def apply_all_cicd_services(
    config_dir_path: str,
    tf_modules_dir: str,
    acc_tf_output_dir: str,
    package_build_dir: str,
):
    tuc = load_terraform_user_config(
        config_dir_path=config_dir_path, tf_modules_dir=tf_modules_dir
    )

    account_services = tuc.account_services
    for acc_serv in account_services:
        for service in acc_serv.services:
            if isinstance(service, CICDConfigModel):
                if isinstance(service.packages, type(None)):
                    print(
                        f"\n{acc_serv.account_name} account does not have defined "
                        "package configurations, skipping."
                    )
                    continue
                else:
                    apply_account_cicd_services(
                        ccm=service,
                        acc_name=acc_serv.account_name,
                        acc_tf_output_dir=acc_tf_output_dir,
                        profile=tuc.header.aws_profiles.identity_center.profile,
                        organization_name=tuc.header.org_name,
                        organization_email=tuc.header.org_email,
                        package_build_dir=package_build_dir,
                    )
