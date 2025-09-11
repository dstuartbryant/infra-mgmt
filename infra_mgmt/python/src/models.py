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


class ProjectCidrBlocks(BaseModel):
    project_name: str
    vpc_cidr_block: str
    subnet_cidr_block: str
    client_vpn_endpoint_client_cidr_block: str

    @property
    def client_cidr(self) -> str:
        """Made this property solely to avoid flake8 line length complaints."""
        return self.client_vpn_endpoint_client_cidr_block


def update_nth_octet_from_base(base: str, n: int, update_to: str) -> str:
    """Updates the nth octet from a base CIDR block

    Args:
        base (str): Base CIDR block
        n (int): Indicates first, second, third, or fourth octet; can be 1, 2, 3, or 4
        update_to (str): What to change the nth octet to

    Returns:
        (str): Updated CIDR block
    """
    split_base = base.split("/")
    octets = split_base[0].split(".")
    subnet_mask = split_base[1]  # a.k.a. "prefix length"
    idx_to_change = n - 1
    octets[idx_to_change] = update_to

    return ".".join(octets) + f"/{subnet_mask}"


class SsoCertificate(BaseModel):
    """Models Terraform user configurations for VPN/VPC SSO certificate"""

    common_name: str
    organization: str


class VpnVpc(BaseModel):
    """Models Terraform user configurations for VPN/VPC setup in accounts"""

    vpc_cidr_block_base: str
    subnet_cidr_block: str
    client_cidr_block_base: str
    sso_certificate: SsoCertificate
    project_octets: dict

    def get_project_cidr_blocks(self, project_name: str) -> ProjectCidrBlocks:
        for pname, octet_dict in self.project_octets.items():
            if pname == project_name:
                return ProjectCidrBlocks(
                    project_name=pname,
                    vpc_cidr_block=update_nth_octet_from_base(
                        self.vpc_cidr_block_base, 2, octet_dict["vpc_and_subnet"]
                    ),
                    subnet_cidr_block=update_nth_octet_from_base(
                        self.subnet_cidr_block, 2, octet_dict["vpc_and_subnet"]
                    ),
                    client_vpn_endpoint_client_cidr_block=update_nth_octet_from_base(
                        self.client_cidr_block_base, 3, octet_dict["client"]
                    ),
                )
        raise ValueError(f"No project named {project_name} found.")


class TerraformUserConfig(BaseModel):
    """Models configuration defined by user that runs Terraform to manage all
    resources
    """

    base_email: str
    aws_profiles: AwsProfiles
    backend: BackendVars
    projects: List[str]
    vpn_vpc: VpnVpc
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
