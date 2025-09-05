"""NEW Models."""

from dataclasses import dataclass
from typing import List

from pydantic import BaseModel


class Name(BaseModel):
    """AWS Identity Center name model"""

    given_name: str
    family_name: str


class User(BaseModel):
    """AWS Identity Center user model"""

    display_name: str
    user_name: str
    name: Name
    email: str
    groups: List[str]


class AwsProfile(BaseModel):
    """AWS profile model used to set permissions for AWS resource managment"""

    profile: str
    region: str


class AwsProfiles(BaseModel):
    """Collection of various AWS profiles used with Terraform configs"""

    backend: AwsProfile
    identity_center: AwsProfile
    org_west: AwsProfile


class BackendVars(BaseModel):
    """Backend (bootstrap) variables"""

    bucket_name: str
    dynamodb_table_name: str


class TerraformUserConfig(BaseModel):
    """Models configuration defined by user that runs Terraform to manage all
    resources
    """

    base_email: str
    aws_profiles: AwsProfiles
    backend: BackendVars
    projects: List[str]
    groups: List[str]
    group_accounts: dict
    unclass_users: List[User]
    secret_users: List[User]


class Account(BaseModel):
    name: str
    account_arns: str
    account_ids: str
    assumable_role_arns: str
    landing_parent_ids: str

    @property
    def alias(self) -> str:
        return self.name.replace("-", "_")


class AccountsList(BaseModel):
    accounts: List[Account]

    def get_account_id(self, name) -> str:
        for acc in self.accounts:
            if acc.name == name:
                return acc.account_ids
        ValueError(f"Account with name {name} not found.")

    def get_account_arn(self, name) -> str:
        for acc in self.accounts:
            if acc.name == name:
                return acc.account_arns
        ValueError(f"Account with name {name} not found.")


@dataclass
class InitIamParam:
    profile: str
    region: str
    relative_module_path: str
