# Makefile for managing the AWS infrastructure


# .ONESHELL Tells Make to execute all lines within a recipe in a single shell instance. 
# This is crucial for heredocs to work correctly, as they are a shell feature and 
# require the entire block to be processed by a single shell.
.ONESHELL:


# Variables
# TF_STATE_BACKEND_DIR := infra_mgmt/bootstrap/state-backend
# TF_ORG_DIR := infra_mgmt/org
# TF_ENVS_DIR := infra_mgmt/environments

# Absolute path to the directory containing this Makefile
MAKEFILE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# User configs dir
USER_CONFIG_DIR := $(MAKEFILE_DIR)/proto_configs
PROJECTS_CONFIG := $(USER_CONFIG_DIR)/projects.yaml

# "Package" dir
INFRA_DIR := $(MAKEFILE_DIR)/infra_mgmt

# Overall collection of Terraform projects
TERRAFORM_DIR := $(INFRA_DIR)/terraform
BUILD_DIR := $(TERRAFORM_DIR)/.build

# Terraform (bootstrapped) backend dir and files
BACKEND_DIR := $(TERRAFORM_DIR)/backend
BACKEND_OUTPUT := $(BACKEND_DIR)/bootstrap.json
BACKEND_HCL := $(BACKEND_DIR)/backend.hcl

CONFIG_DIR := $(TERRAFORM_DIR)/.config
ACCOUNTS_CONFIG := $(CONFIG_DIR)/accounts.json
ACCOUNTS_OUTPUT := $(CONFIG_DIR)/accounts_output.json

# Terraform accounts creation mgmt
CREATE_ACCOUNTS_DIR := $(TERRAFORM_DIR)/create_accounts

# Initial IAM user mgmt
INIT_IAM_DIR := $(BUILD_DIR)/initial_iam
INIT_IAM_CONFIG := $(CONFIG_DIR)/iam_users.json
INIT_IAM_OUTPUT := $(CONFIG_DIR)/iam_output.json

# Terraform org mgmt
ORG_DIR := $(TERRAFORM_DIR)/.build/testProjectA_unclassified

.PHONY: all show-paths bootstrap backend-config accounts org

# Default target
all: bootstrap backend-config accounts org

show-paths:
	@echo "Makefile dir: $(MAKEFILE_DIR)"
	@echo "Bootstrap dir: $(BACKEND_DIR)"

# Step 1: Apply bootstrap (creates S3 + DynamoDB backend infra)
bootstrap:
	@echo "\n>>> Bootstrapping backend..."
	terraform -chdir=$(BACKEND_DIR) init -upgrade
	terraform -chdir=$(BACKEND_DIR) apply -auto-approve

# Step 2: Generate backend.hcl file from bootstrap outputs
backend-config: bootstrap
	@echo "\n>>> Generating backend.hcl from bootstrap outputs..."
	@cat > $(BACKEND_HCL) <<EOF
	bucket         = "$$(terraform -chdir=$(BACKEND_DIR) output -raw s3_bucket_name)"
	dynamodb_table = "$$(terraform -chdir=$(BACKEND_DIR) output -raw dynamodb_table_name)"
	region         = "$$(terraform -chdir=$(BACKEND_DIR) output -raw region)"
	profile        = "$$(terraform -chdir=$(BACKEND_DIR) output -raw profile)"
	EOF
	@echo "backend.hcl created:"
	@cat $(BACKEND_HCL)


accounts-init: backend-config
	@echo "\n>>> Initializing for accounts..."
	terraform -chdir=$(CREATE_ACCOUNTS_DIR) init \
	  -backend-config=$(BACKEND_HCL) \
	  -backend-config="key=accounts/terraform.tfstate"

accounts-plan: 
	@echo "\n>>> Planning accounts..."
	terraform -chdir=$(CREATE_ACCOUNTS_DIR) plan -var-file=$(ACCOUNTS_CONFIG)

accounts-apply: 
	@echo "\n>>> Applying accounts..."
	terraform -chdir=$(CREATE_ACCOUNTS_DIR) apply -auto-approve -var-file=$(ACCOUNTS_CONFIG)

accounts-output: 
	@echo "\n>>> Fetching accounts output..."
	terraform -chdir=$(CREATE_ACCOUNTS_DIR) output -json > $(ACCOUNTS_OUTPUT)

init-iam-init: backend-config
	@echo "\n>>> Initializing for init-iam..."
	terraform -chdir=$(INIT_IAM_DIR) init \
	  -backend-config=$(BACKEND_HCL) \
	  -backend-config="key=init_iam/terraform.tfstate"

init-iam-plan: 
	@echo "\n>>> Planning init-iam..."
	terraform -chdir=$(INIT_IAM_DIR) plan -var-file=$(INIT_IAM_CONFIG)

init-iam-apply: 
	@echo "\n>>> Applying init-iam..."
	terraform -chdir=$(INIT_IAM_DIR) apply -auto-approve -var-file=$(INIT_IAM_CONFIG)

init-iam-output: 
	@echo "\n>>> Fetching init-iam output..."
	terraform -chdir=$(INIT_IAM_DIR) output -json > $(INIT_IAM_OUTPUT)


org-init: backend-config
	@echo "\n>>> Initializing for org management..."
	terraform -chdir=$(ORG_DIR) init \
	  -backend-config=$(BACKEND_HCL) \
	  -backend-config="key=org/terraform.tfstate"

org-console: 
	@echo "\n>>> Org console..."
	terraform -chdir=$(ORG_DIR) console

org-plan: 
	@echo "\n>>> Planning org..."
	terraform -chdir=$(ORG_DIR) plan

# # Step 4: Init + Apply org with backend
# org: accounts backend-config
# 	@echo ">>> Deploying org..."
# 	terraform -chdir=org init -reconfigure \
# 	  -backend-config=../backend.hcl \
# 	  -backend-config="key=org/terraform.tfstate"
# 	terraform -chdir=org apply -auto-approve
