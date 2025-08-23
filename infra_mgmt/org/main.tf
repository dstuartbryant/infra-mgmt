# Load projects, access, and services configs
locals {
  projects = yamldecode(file("${path.module}/../configs/projects.yaml")).projects
  access_by_classification = {
    unclassified = yamldecode(file("${path.module}/../configs/access.unclassified.yaml"))
    secret       = yamldecode(file("${path.module}/../configs/access.secret.yaml"))
  }
  services_by_project = yamldecode(file("${path.module}/../configs/services.yaml")).services

  environments = flatten([
    for proj in local.projects : [
      for classif in proj.classifications : {
        project        = proj.name
        classification = classif
        access         = local.access_by_classification[classif]
        services       = try(local.services_by_project[proj.name][classif], [])
        provider_alias = "${proj.name}-${classif}"
      }
    ]
  ])

  accounts_to_create = {
    for env in local.environments : "${env.project}-${env.classification}" => {
      name      = "${env.project}-${env.classification}"
      email     = "${replace(env.project, "_", "-")}-${replace(env.classification, "_", "-")}@${var.account_email_domain}"
      role_name = "OrganizationAccountAccessRole"
    }
  }
}

# Create new AWS accounts dynamically
resource "aws_organizations_account" "new" {
  for_each = local.accounts_to_create

  name      = each.value.name
  email     = each.value.email
  role_name = each.value.role_name
}

# Combine existing + new accounts
locals {
  accounts = merge(
    var.existing_accounts,
    { for k, acct in aws_organizations_account.new : k => {
        account_id = acct.id
        region     = "us-west-2"
      }
    }
  )
}

module "environments" {
  for_each = { for env in local.environments : "${env.project}-${env.classification}" => env }

  source         = "../modules/environment"
  project        = each.value.project
  classification = each.value.classification
  access         = each.value.access
  services       = each.value.services
  provider_alias = each.value.provider_alias

  providers = { aws = aws[each.value.provider_alias] }
}
