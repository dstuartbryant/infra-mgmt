from typing import List, Optional

import boto3


def get_boto3_session(
    profile: str,
    region: str,
    account_id_to_assume: Optional[str] = None,
    role_name_to_assume: str = "OrganizationAccountAccessRole",
) -> boto3.Session:
    """
    Gets a boto3 session.
    If an account ID is provided and it differs from the profile's account,
    it assumes a role in the target account.
    If the account ID is the same as the profile's, it uses the profile directly.

    Args:
        profile: The AWS profile to use for the initial session.
        region: The AWS region.
        account_id_to_assume: The ID of the account to operate in.
        role_name_to_assume: The name of the role to assume if needed.

    Returns:
        A boto3 session.
    """
    # Create a session using the direct profile first
    base_session = boto3.Session(profile_name=profile, region_name=region)

    if account_id_to_assume:
        # Check the account ID of the current session
        sts_client = base_session.client("sts")
        try:
            caller_identity = sts_client.get_caller_identity()
            current_account_id = caller_identity["Account"]
        except Exception as e:
            print(f"Error getting caller identity for profile '{profile}': {e}")
            raise

        # If the target account is the same as the current one, no need to assume role
        if current_account_id == account_id_to_assume:
            print(
                f"Already in target account {current_account_id}. Using profile"
                f" '{profile}' directly."
            )
            return base_session

        # If target account is different, proceed with assuming role
        role_arn = f"arn:aws:iam::{account_id_to_assume}:role/{role_name_to_assume}"
        try:
            print(f"Assuming role {role_arn}...")
            assumed_role_object = sts_client.assume_role(
                RoleArn=role_arn, RoleSessionName="AssumedRoleSession"
            )
            credentials = assumed_role_object["Credentials"]

            # Create a new session with the assumed role's temporary credentials
            return boto3.Session(
                aws_access_key_id=credentials["AccessKeyId"],
                aws_secret_access_key=credentials["SecretAccessKey"],
                aws_session_token=credentials["SessionToken"],
                region_name=region,
            )
        except Exception as e:
            print(f"Error assuming role {role_arn}: {e}")
            raise
    else:
        # If no account ID is specified, just use the base session
        return base_session


def list_s3_folders(
    profile: str,
    region: str,
    bucket_name: str,
    account_id_to_assume: Optional[str] = None,
) -> List[str]:
    """
    Lists the folders in an S3 bucket, potentially in another account.

    Args:
        profile: The AWS profile to use.
        region: The AWS region to use.
        bucket_name: The name of the S3 bucket.
        account_id_to_assume: The ID of the account where the bucket resides.

    Returns:
        A list of folder names in the S3 bucket.
    """
    try:
        session = get_boto3_session(profile, region, account_id_to_assume)
        s3_client = session.client("s3")
        folders = []
        paginator = s3_client.get_paginator("list_objects_v2")
        pages = paginator.paginate(Bucket=bucket_name, Delimiter="/")
        for page in pages:
            if "CommonPrefixes" in page:
                for prefix in page["CommonPrefixes"]:
                    folders.append(prefix.get("Prefix"))
        return folders
    except Exception as e:
        print(f"An error occurred listing S3 folders: {e}")
        return []


def list_codeartifact_packages(
    profile: str,
    region: str,
    domain: str,
    repository: str,
    account_id_to_assume: Optional[str] = None,
) -> List[str]:
    """
    Lists the packages in a CodeArtifact repo, potentially in another account.

    Args:
        profile: The AWS profile to use.
        region: The AWS region to use.
        domain: The CodeArtifact domain.
        repository: The CodeArtifact repository.
        account_id_to_assume: The ID of the account where CodeArtifact resides.

    Returns:
        A list of packages in the CodeArtifact repo.
    """
    try:
        session = get_boto3_session(profile, region, account_id_to_assume)
        codeartifact_client = session.client("codeartifact")
        packages = []
        paginator = codeartifact_client.get_paginator("list_packages")
        pages = paginator.paginate(domain=domain, repository=repository)
        for page in pages:
            for package in page.get("packages", []):
                packages.append(package["package"])
        return packages
    except Exception as e:
        print(f"An error occurred listing CodeArtifact packages: {e}")
        return []


def get_codeartifact_authorization_token(
    profile: str,
    region: str,
    domain: str,
    domain_owner: str,
    duration_seconds: int = 3600,
    account_id_to_assume: Optional[str] = None,
) -> Optional[str]:
    """
    Gets an authorization token from AWS CodeArtifact.

    Args:
        profile: The AWS profile to use.
        region: The AWS region.
        domain: The CodeArtifact domain.
        domain_owner: The AWS account ID of the domain owner.
        duration_seconds: The duration for which the authorization token is valid.
        account_id_to_assume: The ID of the account where CodeArtifact resides.

    Returns:
        The authorization token, or None if an error occurred.
    """
    try:
        session = get_boto3_session(profile, region, account_id_to_assume)
        codeartifact_client = session.client("codeartifact")
        response = codeartifact_client.get_authorization_token(
            domain=domain, domainOwner=domain_owner, durationSeconds=duration_seconds
        )
        return response.get("authorizationToken")
    except Exception as e:
        print(f"An error occurred getting CodeArtifact authorization token: {e}")
        return None


def upload_zip_to_s3(
    profile: str,
    region: str,
    local_zip_path: str,
    bucket_name: str,
    s3_key: str,
    account_id_to_assume: Optional[str] = None,
) -> bool:
    """
    Uploads a local .zip archive to a specified S3 bucket.

    Args:
        profile: The AWS profile to use.
        region: The AWS region.
        local_zip_path: The local path to the .zip file.
        bucket_name: The name of the S3 bucket.
        s3_key: The key (path) for the uploaded object in the S3 bucket.
        account_id_to_assume: The ID of the account where the bucket resides.

    Returns:
        True if the upload was successful, False otherwise.
    """
    try:
        session = get_boto3_session(profile, region, account_id_to_assume)
        s3_client = session.client("s3")
        s3_client.upload_file(local_zip_path, bucket_name, s3_key)
        print(f"Successfully uploaded {local_zip_path} to s3://{bucket_name}/{s3_key}")
        return True
    except Exception as e:
        print(f"An error occurred uploading to S3: {e}")
        return False


def download_latest_zip_from_s3(
    profile: str,
    region: str,
    bucket_name: str,
    local_download_dir: str,
    account_id_to_assume: Optional[str] = None,
) -> Optional[str]:
    """
    Downloads the most recently uploaded .zip archive from a given S3 bucket.

    Args:
        profile: The AWS profile to use.
        region: The AWS region.
        bucket_name: The name of the S3 bucket.
        local_download_dir: The local directory to download the file to.
        account_id_to_assume: The ID of the account where the bucket resides.

    Returns:
        The local path to the downloaded file, or None if no file was found or an error occurred.
    """
    try:
        session = get_boto3_session(profile, region, account_id_to_assume)
        s3_client = session.client("s3")

        # List all objects in the bucket
        paginator = s3_client.get_paginator("list_objects_v2")
        pages = paginator.paginate(Bucket=bucket_name)
        all_objects = [obj for page in pages for obj in page.get("Contents", [])]

        if not all_objects:
            print(f"No objects found in bucket '{bucket_name}'.")
            return None

        # Find the most recently modified object
        latest_object = max(all_objects, key=lambda obj: obj["LastModified"])
        latest_object_key = latest_object["Key"]
        print(f"Found latest object: '{latest_object_key}'")

        # Download the file
        import os

        if not os.path.exists(local_download_dir):
            os.makedirs(local_download_dir)
        local_file_path = os.path.join(local_download_dir, latest_object_key)

        print(f"Downloading to {local_file_path}...")
        s3_client.download_file(bucket_name, latest_object_key, local_file_path)
        print("Download successful.")

        return local_file_path
    except Exception as e:
        print(f"An error occurred downloading from S3: {e}")
        return None


if __name__ == "__main__":
    # --- Configuration ---
    # Profile with permissions to assume roles in other accounts
    admin_profile = "my-admin-profile"
    aws_region = "us-east-1"

    # --- Scenario 1: Accessing resources in the same (admin) account ---
    print("--- Accessing resources in admin account ---")
    # Your S3 bucket and CodeArtifact repo in the admin account
    admin_s3_bucket = "your-admin-account-s3-bucket"
    admin_ca_domain = "your-admin-account-ca-domain"
    admin_ca_repo = "your-admin-account-ca-repo"

    s3_folders_admin = list_s3_folders(admin_profile, aws_region, admin_s3_bucket)
    print(f"Folders in S3 bucket '{admin_s3_bucket}': {s3_folders_admin}")

    ca_packages_admin = list_codeartifact_packages(
        admin_profile, aws_region, admin_ca_domain, admin_ca_repo
    )
    print(f"Packages in CodeArtifact repo '{admin_ca_repo}': {ca_packages_admin}")
    print("-" * 40)

    # --- Scenario 2: Accessing resources in a managed account via STS AssumeRole ---
    print("\n--- Accessing resources in a managed account ---")
    # The AWS Account ID of the managed account you want to access
    managed_account_id = (
        "123456789012"  # <-- IMPORTANT: Replace with the target account ID
    )

    # S3 bucket and CodeArtifact repo in the managed account
    managed_s3_bucket = "your-managed-account-s3-bucket"
    managed_ca_domain = "your-managed-account-ca-domain"
    managed_ca_repo = "your-managed-account-ca-repo"

    s3_folders_managed = list_s3_folders(
        admin_profile,
        aws_region,
        managed_s3_bucket,
        account_id_to_assume=managed_account_id,
    )
    print(
        f"Folders in S3 bucket '{managed_s3_bucket}' (in account "
        f"{managed_account_id}): {s3_folders_managed}"
    )

    ca_packages_managed = list_codeartifact_packages(
        admin_profile,
        aws_region,
        managed_ca_domain,
        managed_ca_repo,
        account_id_to_assume=managed_account_id,
    )
    print(
        f"Packages in CodeArtifact repo '{managed_ca_repo}' (in account "
        f"{managed_account_id}): {ca_packages_managed}"
    )
    print("-" * 40)

    # --- Scenario 3: Getting a CodeArtifact Authorization Token for a managed
    # account ---
    print("\n--- Getting CodeArtifact Token for a managed account ---")
    # The domain owner is often the same as the managed account ID
    managed_ca_domain_owner = managed_account_id

    token = get_codeartifact_authorization_token(
        admin_profile,
        aws_region,
        managed_ca_domain,
        domain_owner=managed_ca_domain_owner,
        account_id_to_assume=managed_account_id,
    )

    if token:
        print(
            f"Successfully retrieved CodeArtifact token for domain "
            f"'{managed_ca_domain}' in account '{managed_account_id}'"
        )
        # print(f"Token: {token}") # Uncomment to display token
    else:
        print("Failed to retrieve CodeArtifact token.")
    print("-" * 40)

    # --- Scenario 4: Uploading a file to S3 in a managed account ---
    print("\n--- Uploading a file to S3 in a managed account ---")
    # Create a dummy zip file for testing
    dummy_zip_path = "test.zip"
    with open(dummy_zip_path, "w") as f:
        f.write("This is a test file.")
    import zipfile

    with zipfile.ZipFile(dummy_zip_path, "w") as zf:
        zf.writestr("test.txt", "This is a test file.")

    s3_key = f"backups/{dummy_zip_path}"
    upload_success = upload_zip_to_s3(
        admin_profile,
        aws_region,
        dummy_zip_path,
        managed_s3_bucket,
        s3_key,
        account_id_to_assume=managed_account_id,
    )
    if upload_success:
        print("File upload successful.")
    else:
        print("File upload failed.")

    # Clean up the dummy file
    import os

    os.remove(dummy_zip_path)
    print("-" * 40)

    # --- Scenario 5: Downloading the latest backup from S3 in a managed account ---
    print("\n--- Downloading latest backup from S3 in a managed account ---")
    download_dir = "temp_downloads"
    downloaded_file = download_latest_zip_from_s3(
        admin_profile,
        aws_region,
        managed_s3_bucket,
        download_dir,
        account_id_to_assume=managed_account_id,
    )
    if downloaded_file:
        print(f"File downloaded to: {downloaded_file}")
        # Clean up the downloaded file and directory
        import shutil

        shutil.rmtree(download_dir)
        print("Cleaned up temporary download directory.")
    else:
        print("File download failed.")
    print("-" * 40)
