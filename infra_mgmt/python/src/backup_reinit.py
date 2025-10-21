"""Backup/Reinit module."""

import shutil
import tempfile
from datetime import datetime
from os import mkdir, path, walk

from infra_mgmt.python.src.services.python_package.aws import upload_zip_to_s3
from infra_mgmt.python.src.terraform.config import load_terraform_user_config

CURR_DIR = path.dirname(path.abspath(__file__))  # infra_mgmt/python/src
PYTHON_DIR = path.dirname(path.abspath(CURR_DIR))  # infra_mgmt/python
INFRA_MGMT_DIR = path.dirname(path.abspath(PYTHON_DIR))  # infra_mgmt
PROJECT_DIR = path.dirname(path.abspath(INFRA_MGMT_DIR))  # project dir

TF_DIR = path.join(INFRA_MGMT_DIR, "terraform")

TF_BUILD_DIR = path.join(TF_DIR, ".build")
TF_BUILD_ACCOUNTS_DIR = path.join(TF_BUILD_DIR, "accounts")
TF_BUILD_ACCOUNTS_OUTPUT_DIR = path.join(TF_BUILD_ACCOUNTS_DIR, ".output")

TF_CLIENT_VPN_CONFIGS_DIR = path.join(TF_DIR, ".client_vpn_configs")

TF_CONFIG_DIR = path.join(TF_DIR, ".config")

TF_LOGS_DIR = path.join(TF_DIR, ".logs")

TF_BACKEND_DIR = path.join(TF_DIR, "backend")

TF_ORG_DIR = path.join(TF_DIR, "org")

USER_CONFIGS_DIR = path.join(PROJECT_DIR, "user_configs")

GENERATED_VPN_CONFIGS_DIR = path.join(PROJECT_DIR, "generated_vpn_configs")

# Backup Files/Folders
# Each key is a folder path
# If a key's value is the string "all", everything in the folder, to include the folder
#   itself needs to be stashed
# If a key's value is a list of strings, each string identifies the individual files
#   that need to be stashed - underneath their parent folder name in the archive that
#   will be generated
# If a key's value is a string starting with `*`, then any sub-folder containing a file
#  with the name following the `*` must be stashed, filed under its parent folder name
BACKUP_PATHS = {
    GENERATED_VPN_CONFIGS_DIR: "all",
    TF_BUILD_ACCOUNTS_OUTPUT_DIR: "all",
    TF_BUILD_ACCOUNTS_DIR: "*terraform.tfvars",
    TF_CLIENT_VPN_CONFIGS_DIR: "all",
    TF_CONFIG_DIR: "all",
    TF_LOGS_DIR: "all",
    TF_BACKEND_DIR: ["backend.hcl", "terraform.tfvars"],
    TF_ORG_DIR: ["terraform.tfvars"],
    USER_CONFIGS_DIR: "all",
}


def find_files_by_name(directory, file_name):
    """
    Finds all files with a specific name in a directory and its subdirectories,
    returning their absolute paths.

    Args:
        directory (str): The path to the starting directory.
        file_name (str): The name of the file to search for.

    Returns:
        list: A list of absolute paths to the found files.
    """
    found_files = []
    for root, _, files in walk(directory):
        for f in files:
            if f == file_name:
                absolute_path = path.abspath(path.join(root, f))
                found_files.append(absolute_path)
    return found_files


def zip_directory_to_temp_archive(source_directory):
    """
    Zips a given directory into an archive within a temporary directory.
    The caller is responsible for cleaning up the returned temporary directory
    by calling the cleanup() method on the returned object.

    Args:
        source_directory (str): The path to the directory to be zipped.

    Returns:
        tuple: A tuple containing:
            - str: The full path to the created zip archive.
            - tempfile.TemporaryDirectory: The temporary directory object.
    """
    temp_dir_obj = tempfile.TemporaryDirectory()
    temp_dir = temp_dir_obj.name
    try:
        archive_path_without_extension = path.join(
            temp_dir, path.basename(source_directory)
        )
        archive_full_path = shutil.make_archive(
            base_name=archive_path_without_extension,
            format="zip",
            root_dir=path.dirname(source_directory),
            base_dir=path.basename(source_directory),
        )
        print(f"Archive created at: {archive_full_path}")
        return archive_full_path, temp_dir_obj
    except Exception as e:
        # Clean up the temp directory if something goes wrong
        temp_dir_obj.cleanup()
        raise e


def generate_backup_archive(config_dir_path: str, tf_modules_dir: str):
    """Generates instantaneous project configurations backup .zip archive and uploads
    it to the AWS Organization's Management account's purpose-made S3 bucket.

    Args:
        config_dir_path (str): Path to the user configs directory.
        tf_modules_dir (str): Path to the terraform modules directory.
    """
    # Create a temporary directory for building the archive contents
    with tempfile.TemporaryDirectory() as staging_dir:
        for bpdir in BACKUP_PATHS:
            content_switch = BACKUP_PATHS[bpdir]
            if path.isdir(bpdir):
                if isinstance(content_switch, str):
                    if content_switch == "all":
                        source_directory = bpdir
                        destination_directory = path.join(
                            staging_dir, path.basename(bpdir)
                        )
                        shutil.copytree(source_directory, destination_directory)
                    elif content_switch[0] == "*":
                        fname = content_switch.split("*")[1]
                        target_fpaths = find_files_by_name(bpdir, fname)
                        for tfp in target_fpaths:
                            source_file = tfp
                            destination_file_path = path.join(
                                staging_dir, source_file.replace("/", "__")[2:]
                            )
                            shutil.copy(source_file, destination_file_path)

                elif isinstance(content_switch, list):
                    one_level_up = path.dirname(path.abspath(bpdir))
                    new_base_name = path.basename(one_level_up)
                    new_base_dest = path.join(staging_dir, new_base_name)
                    if not path.isdir(new_base_dest):
                        mkdir(new_base_dest)
                    new_sub_base_name = path.join(new_base_name, path.basename(bpdir))
                    new_sub_base_dest = path.join(staging_dir, new_sub_base_name)
                    if not path.isdir(new_sub_base_dest):
                        mkdir(new_sub_base_dest)

                    for fname in content_switch:
                        source_path = path.join(bpdir, fname)
                        dest_path = path.join(new_sub_base_dest, fname)
                        shutil.copy(source_path, dest_path)

        archive_path, archive_temp_dir_obj = zip_directory_to_temp_archive(staging_dir)

        # Get the current datetime object
        current_datetime = datetime.now()
        formatted_datetime_string = current_datetime.strftime("%Y-%m-%dT%H-%M-%SZ")

        tuc = load_terraform_user_config(
            config_dir_path=config_dir_path, tf_modules_dir=tf_modules_dir
        )

        upload_zip_to_s3(
            profile=tuc.header.aws_profiles.identity_center.profile,
            region=tuc.header.aws_profiles.identity_center.region,
            local_zip_path=archive_path,
            bucket_name=tuc.header.backup.bucket_name,
            s3_key=f"{formatted_datetime_string}.zip",
            account_id_to_assume=tuc.header.backup.account_id,
        )

        # Clean up the temporary directory containing the archive
        archive_temp_dir_obj.cleanup()
