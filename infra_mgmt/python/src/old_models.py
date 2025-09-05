"""Models."""

from typing import List

from pydantic import BaseModel, model_validator
from typing_extensions import Self


class ProjectError(Exception):
    pass


class Project(BaseModel):
    name: str
    classifications: List[str]


class Projects(BaseModel):
    # This email address will be used for plus addressing to make the required unique
    # addresses for AWS accounts
    base_email: str
    projects: List[Project]

    def get_project(self, name: str) -> Project:
        for p in self.projects:
            if name == p.name:
                return p
        raise ProjectError(f"Project with name {name} not found.")


class Account(BaseModel):
    name: str
    account_arns: str
    account_ids: str
    assumable_role_arns: str
    landing_parent_ids: str

    @property
    def alias(self) -> str:
        return self.name.replace("-", "_")


class User(BaseModel):
    username: str
    email: str
    projects: List[str]
    groups: List[str]


class AccessConfig(BaseModel):
    groups: List[str]
    users: List[User]

    @model_validator(mode="after")
    def cross_check_groups(self) -> Self:
        for user in self.users:
            for grp in user.groups:
                if grp not in self.groups:
                    raise ValueError(
                        f"Unexpected group found for user {user.username}: {grp}. "
                        f"Expecting one of {", ".join(self.groups)}"
                    )
        return self
