"""NEW Models."""

from dataclasses import dataclass
from typing import List, Literal, Optional, Union

from pydantic import BaseModel


class AwsProfile(BaseModel):
    """AWS profile model used to set permissions for AWS resource managment"""

    profile: str
    region: str


class AwsProfiles(BaseModel):
    """Collection of various AWS profiles used with Terraform configs"""

    backend: AwsProfile
    identity_center: AwsProfile
    org_main: AwsProfile


class BackendVars(BaseModel):
    """Backend (bootstrap) variables"""

    bucket_name: str
    dynamodb_table_name: str


class HeaderConfigModel(BaseModel):
    base_email: str
    org_prefix: str
    org_name: str
    org_alias: str
    org_email: str
    aws_profiles: AwsProfiles
    backend: BackendVars
    parent_id: str
    managed_accounts: dict


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
    vpn_access: bool = False


class IamConfigModel(BaseModel):
    groups: List[str]
    group_accounts: dict
    users: List[User]


class PythonPackageConfigModel(BaseModel):
    name: str
    terminal_background_color: str


class CicdPackagesConfigModel(BaseModel):
    python: Optional[List[PythonPackageConfigModel]] = None


class CicdGithubConfigModel(BaseModel):
    owner: str
    repos: List[str]
    codestar_arn: str
    codebuild_project_prefix: str
    branch: str = "main"

    @property
    def repositories(self) -> dict:
        out = {}
        for rp in self.repos:
            out[rp] = f"{self.owner}/{rp}"
        return out


class CICDConfigModel(BaseModel):
    git: Literal["S3", "GitHub"]
    github: Optional[CicdGithubConfigModel] = None
    packages: Optional[CicdPackagesConfigModel] = None

    def get_package_config(self, name: str) -> PythonPackageConfigModel:
        for pack in self.packages.python:
            if pack.name == name:
                return pack
        raise ValueError(f"No package named {name} found")


class ProjectCidrBlocks(BaseModel):
    project_name: str
    vpc_cidr_block: str
    subnet_cidr_block: str
    public_subnet_cidr_block: str
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


class ServerCertificate(BaseModel):
    """Models Terraform user configurations for VPN/VPC server certificate"""

    common_name: str
    organization: str


class AccountVpcVpnOctets(BaseModel):
    vpc_and_subnet: str
    client: str


class VpnVpcConfigModel(BaseModel):
    vpc_cidr_block: str
    subnet_cidr_block: str
    public_subnet_cidr_block: str
    client_vpn_endpoint_client_cidr_block: str
    octets: AccountVpcVpnOctets

    @property
    def client_cidr(self) -> str:
        """Made this property solely to avoid flake8 line length complaints."""
        return self.client_vpn_endpoint_client_cidr_block


class TestWebAppConfigModel(BaseModel):
    dummy_field: bool = True


class AccountServicesConfig(BaseModel):
    account_name: str
    services: List[Union[CICDConfigModel, VpnVpcConfigModel, TestWebAppConfigModel]]


class VpcVpnHeaderConfigModel(BaseModel):
    """Models Terraform user configurations for VPN/VPC setup in accounts"""

    vpc_cidr_block_base: str
    subnet_cidr_block: str
    public_subnet_cidr_block_base: str
    client_cidr_block_base: str
    server_certificate: ServerCertificate

    def get_project_cidr_blocks(
        self, acc_octets: AccountVpcVpnOctets
    ) -> VpnVpcConfigModel:
        return VpnVpcConfigModel(
            vpc_cidr_block=update_nth_octet_from_base(
                self.vpc_cidr_block_base, 2, acc_octets.vpc_and_subnet
            ),
            subnet_cidr_block=update_nth_octet_from_base(
                self.subnet_cidr_block, 2, acc_octets.vpc_and_subnet
            ),
            public_subnet_cidr_block=update_nth_octet_from_base(
                self.public_subnet_cidr_block_base,
                2,
                acc_octets.vpc_and_subnet,
            ),
            client_vpn_endpoint_client_cidr_block=update_nth_octet_from_base(
                self.client_cidr_block_base, 3, acc_octets.client
            ),
            octets=acc_octets,
        )


class TerraformUserConfig(BaseModel):
    """Models configuration defined by user that runs Terraform to manage all
    resources
    """

    header: HeaderConfigModel
    iam: IamConfigModel
    vpc_header: VpcVpnHeaderConfigModel
    account_services: List[AccountServicesConfig]

    def model_post_init(self, context):
        self.vpc_header.server_certificate.organization = self.header.org_name
        self.vpc_header.server_certificate.common_name = self.header.org_alias
        return super().model_post_init(context)

    def get_services_for_account(self, account_name: str) -> AccountServicesConfig:
        for acc_serv in self.account_services:
            if acc_serv.account_name == account_name:
                return acc_serv.services
        raise ValueError(f"No account named {account_name} found in account services.")


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
