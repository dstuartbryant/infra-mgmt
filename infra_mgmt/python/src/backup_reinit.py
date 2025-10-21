"""Backup/Reinit module."""

import shutil
import tempfile
from copy import deepcopy
from datetime import datetime
from os import listdir, mkdir, path, remove, walk

import yaml

from infra_mgmt.python.src.services.python_package.aws import (
    download_latest_zip_from_s3,
    upload_zip_to_s3,
)
from infra_mgmt.python.src.terraform.config import load_terraform_user_config
from infra_mgmt.python.src.terraform.models import ReinitConfig

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

SERVICES_DIR = path.join(INFRA_MGMT_DIR, "services")

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


PURGE_PATHS = {
    GENERATED_VPN_CONFIGS_DIR: "all",
    SERVICES_DIR: "all",
    TF_BUILD_DIR: "all",
    TF_CLIENT_VPN_CONFIGS_DIR: "all",
    TF_CONFIG_DIR: "all",
    TF_LOGS_DIR: "all",
    TF_BACKEND_DIR: ["backend.hcl", "terraform.tfvars"],
    TF_ORG_DIR: [".terraform", ".terraform.lock.hcl", "terraform.tfvars"],
    USER_CONFIGS_DIR: "all",
}

RESTORE_PATHS = [
    TF_CLIENT_VPN_CONFIGS_DIR,
    TF_CONFIG_DIR,
    TF_LOGS_DIR,
    GENERATED_VPN_CONFIGS_DIR,
    USER_CONFIGS_DIR,
    TF_BACKEND_DIR,
    TF_ORG_DIR,
    TF_BUILD_ACCOUNTS_DIR,
    TF_BUILD_ACCOUNTS_OUTPUT_DIR,
]


class RestoreError(Exception):
    path


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


def remove_string_from_list(my_list: list, string_to_remove: str) -> list:
    """Removes a string from a list of strings, if it exists.

    Args:
        my_list (list): A list of strings.
        string_to_remove (str): The string to remove from the list.

    Returns:
        list: The updated list.
    """
    if string_to_remove in my_list:
        my_list.remove(string_to_remove)
    return my_list


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


def generate_backup_archive(config_dir_path: str, tf_modules_dir: str) -> None:
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


def purge_configs() -> None:
    """Purges instantaneous project configurations.

    Removes all existing configurations for a current project, in order to clean out
    directories so to work on a different project.
    """
    for pdir in PURGE_PATHS:
        content_switch = PURGE_PATHS[pdir]
        if isinstance(content_switch, str):
            if content_switch == "all":
                if path.isdir(pdir):
                    shutil.rmtree(pdir)
                elif path.isfile(pdir):
                    remove(pdir)
        elif isinstance(content_switch, list):
            for fname in content_switch:
                cpath = path.join(pdir, fname)
                if path.isdir(cpath):
                    shutil.rmtree(cpath)
                elif path.isfile(cpath):
                    remove(cpath)


def load_reinit_config(config_dir_path: str) -> ReinitConfig:
    """Pulls backup configs for project and puts them back in their configuration
    "places".
    Args:
        config_dir_path (str): Path to the user configs directory.

    """
    config_fpath = path.join(config_dir_path, "reinit.yaml")
    ric = yaml.safe_load(open(config_fpath, "r"))

    return ReinitConfig(**ric)


def reinit_project_configs(
    config_dir_path: str, tf_modules_dir: str, local_download_dir: str
) -> None:
    """Pulls backup configs for project and puts them back in their configuration
    "places".
    Args:
        config_dir_path (str): Path to the user configs directory.
        tf_modules_dir (str): Path to the terraform modules directory.
        local_download_dir (str): The local directory to restore the files to.
    """
    ric = load_reinit_config(config_dir_path=config_dir_path)

    # with tempfile.TemporaryDirectory() as temp_dir:
    #     downloaded_zip_path = download_latest_zip_from_s3(
    #         profile=ric.aws_profile.profile,
    #         region=ric.aws_profile.region,
    #         bucket_name=ric.backup.bucket_name,
    #         local_download_dir=temp_dir,
    #         account_id_to_assume=ric.backup.account_id,
    #     )

    #     if downloaded_zip_path:
    #         with tempfile.TemporaryDirectory() as unzip_dir:
    #             print(f"Unzipping {downloaded_zip_path} to {unzip_dir}...")
    #             shutil.unpack_archive(downloaded_zip_path, unzip_dir)

    #             # The archive contains a single directory with the backed-up files.
    #             unzipped_items = listdir(unzip_dir)
    #             if not unzipped_items:
    #                 print("Error: Unzipped archive is empty.")
    #                 return

    #             source_content_dir = path.join(unzip_dir, unzipped_items[0])

    #             print(
    #                 "Restoring files from"
    #                 f" {source_content_dir} to {local_download_dir}"
    #             )
    #             shutil.copytree(
    #                 source_content_dir, local_download_dir, dirs_exist_ok=True
    #             )
    #             print("Restore complete.")

    for restore_dir in RESTORE_PATHS:
        print(restore_dir)

    contents = listdir(local_download_dir)
    contents.sort()
    print("\n\ncontents:")
    for cnt in contents:
        print(cnt)
    print("\n\n")

    terraform_finds = []
    restored = []
    for restore_dir in RESTORE_PATHS:
        restore_base = path.basename(restore_dir)
        if restore_base in contents:
            contents = remove_string_from_list(contents, restore_base)
            source_path = path.join(local_download_dir, restore_base)
            dest_path = restore_dir
            if path.isdir(source_path):
                shutil.copytree(source_path, dest_path, dirs_exist_ok=True)
            restored.append(restore_dir)
        elif "terraform" in restore_dir:
            terraform_finds.append(restore_dir)

    # Filter out RESTORE_PATHS that have already been used
    restore_paths = deepcopy(RESTORE_PATHS)
    for rd in restored:
        restore_paths = remove_string_from_list(restore_paths, rd)

    # Restore terraform/backend and terraform/org content
    restored = []
    for rp in restore_paths:
        if "terraform" in rp and "backend" in rp:
            if "terraform" in contents:
                source_path = path.join(local_download_dir, "terraform", "backend")
                dest_path = rp
                if path.isdir(source_path):
                    shutil.copytree(source_path, dest_path, dirs_exist_ok=True)
                restored.append(rp)
        if "terraform" in rp and "org" in rp:
            if "terraform" in contents:
                source_path = path.join(local_download_dir, "terraform", "org")
                dest_path = rp
                if path.isdir(source_path):
                    shutil.copytree(source_path, dest_path, dirs_exist_ok=True)
                restored.append(rp)

    # Filter out `terraform` from contents at this point
    contents = remove_string_from_list(contents, "terraform")

    # Filter out RESTORE_PATHS that have already been used
    for rd in restored:
        restore_paths = remove_string_from_list(restore_paths, rd)

    # At this point we should only have account terraform.tfvars files to process
    if len(restore_paths) > 1:
        raise RestoreError(
            f"Number of remaining 'restore paths' is {len(restore_paths)}"
        )
    if restore_paths[0] != TF_BUILD_ACCOUNTS_DIR:
        raise RestoreError(f"Final path to restore is not {TF_BUILD_ACCOUNTS_DIR}")

    restore_path = restore_paths[0]
    print("\n\n")
    for encoded_fpath in contents:
        if "terraform.tfvars" not in encoded_fpath:
            continue
        fpath = "/" + encoded_fpath.replace("__", "/")
        accounts_subdir_name = path.basename(path.dirname(path.abspath(fpath)))
        print(fpath)
        print(f"{accounts_subdir_name}\n")
        rdir = path.join(restore_path, accounts_subdir_name)
        if not path.isdir(rdir):
            mkdir(rdir)
        source_path = path.join(local_download_dir, encoded_fpath)
        dest_path = path.join(rdir, "terraform.tfvars")
        shutil.copy(source_path, dest_path)
    return contents, restore_paths
