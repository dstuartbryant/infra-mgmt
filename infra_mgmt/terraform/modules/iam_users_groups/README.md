# Terraform Module: IAM Users and Groups

This module manages users, groups, permissions, and account assignments within AWS IAM Identity Center (formerly AWS SSO). It is designed to be the central point of control for defining who has access to what across your AWS Organization.

## Core Functionality

-   **User Creation**: Provisions new users in the IAM Identity Center directory.
-   **Group Creation**: Provisions new groups.
-   **Group Membership**: Manages the assignment of users to groups.
-   **Permission Set Creation**: Creates a distinct permission set for each group.
-   **Policy Attachments**: Attaches AWS managed policies to the permission sets.
-   **Account Assignments**: Assigns groups (and their associated permissions) to specific AWS accounts.

This module provides a scalable way to manage your identity infrastructure as code. By modifying the input variables, you can onboard new developers, create new teams, and grant them access to the appropriate AWS accounts in a repeatable manner.

## Input Variables

| Name                  | Description                                                                                                                                                           | Type                                                                                                                            | Default | Required |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------- | :------: |
| `groups`              | A list of group names to create in IAM Identity Center.                                                                                                               | `list(string)`                                                                                                                  | n/a     |   yes    |
| `group_accounts`      | A map where keys are group names and values are a list of AWS Account IDs that the group should have access to.                                                         | `map(list(string))`                                                                                                             | n/a     |   yes    |
| `users`               | A list of user objects to create. See the structure below.                                                                                                            | `list(object({ display_name = string, user_name = string, name = object({ given_name = string, family_name = string }), email = string, groups = list(string) }))` | n/a     |   yes    |
| `group_policy_arns`   | An optional map where keys are group names and values are a list of AWS managed policy ARNs to attach to the group's permission set.                                    | `map(list(string))`                                                                                                             | `{}`    |    no    |

### User Object Structure

The `users` variable expects a list of objects with the following structure:

```hcl
[
  {
    display_name = "John Doe"
    user_name    = "johndoe"
    name = {
      given_name  = "John"
      family_name = "Doe"
    }
    email  = "john.doe@example.com"
    groups = ["group1", "group2"]
  }
]
```

## Outputs

| Name                  | Description                                                              |
| --------------------- | ------------------------------------------------------------------------ |
| `groups`              | A map of the created Identity Center groups (name => group_id).          |
| `users`               | A map of the created Identity Center users (user_name => user details).  |
| `group_memberships`   | A map of the created group memberships (user_name-group_name => membership_id). |
| `permission_sets`     | A map of the created permission sets (group_name => permission_set_arn). |
| `policy_attachments`  | A map of the managed policy attachments.                                 |
| `account_assignments` | A map of the account assignments (group_name-account_id => assignment_id). |
