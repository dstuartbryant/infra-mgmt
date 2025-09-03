"""NEW Models."""

from typing import List

from pydantic import BaseModel, model_validator
from typing_extensions import Self


class Name(BaseModel):
    given_name: str
    family_name: str


class User(BaseModel):
    display_name: str
    user_name: str
    name: Name
    email: str
    groups: List[str]


class TerraformUserConfig(BaseModel):
    base_email: str
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
