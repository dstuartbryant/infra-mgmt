"""Services models module."""

from pydantic import BaseModel

# from ...terraform.models import TerraformUserConfig


class CicdMetadata(BaseModel):
    codeartifact_domain: str
    codeartifact_domain_owner: str
    codeartifact_repo: str
    codeartifact_region: str
    git_s3_bucket: str


class PythonPackageInput(BaseModel):
    dev_container_name: str
    docker_compose_service_name: str
    terminal_background_color: str
    organization_name: str
    organization_email: str
    package_name: str
    codeartifact: CicdMetadata

    @property
    def git_repo_path_with_key(self) -> str:
        return f"{self.codeartifact.git_s3_bucket}/{self.package_name}"
