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
MODULES_DIR := $(TERRAFORM_DIR)/modules

# Terraform (bootstrapped) backend dir and files
BACKEND_DIR := $(TERRAFORM_DIR)/backend
BACKEND_OUTPUT := $(BACKEND_DIR)/bootstrap.json
BACKEND_HCL := $(BACKEND_DIR)/backend.hcl

CONFIG_DIR := $(TERRAFORM_DIR)/.config
ACCOUNTS_CONFIG := $(CONFIG_DIR)/accounts.json
ACCOUNTS_OUTPUT := $(CONFIG_DIR)/accounts_output.json

LOGS_DIR := $(TERRAFORM_DIR)/.logs

# Terraform accounts creation mgmt
ACCOUNTS_DIR := $(TERRAFORM_DIR)/accounts

# Initial IAM user mgmt
IAM_DIR := $(BUILD_DIR)/iam
IAM_CONFIG := $(CONFIG_DIR)/iam_users.json
IAM_OUTPUT := $(CONFIG_DIR)/iam_output.json
IAM_MODULE := $(MODULES_DIR)/iam_users_groups

# Terraform org mgmt
ORG_DIR := $(TERRAFORM_DIR)/.build/org
ORG_OUTPUT_DIR := $(CONFIG_DIR)/org


.PHONY: all show-paths bootstrap backend-init backend-config accounts org

# Default target
all: bootstrap backend-config accounts org

show-paths:
	@echo "Makefile dir: $(MAKEFILE_DIR)"
	@echo "Bootstrap dir: $(BACKEND_DIR)"

# Step 1: Apply bootstrap (creates S3 + DynamoDB backend infra)
bootstrap:
	@echo "\n>>> Generating backend terraform.tfvars..."
	python -m infra_mgmt.python.bin.backend $(USER_CONFIG_DIR)/config.yaml $(BACKEND_DIR)
	@echo "\n>>> Bootstrapping backend..."
	terraform -chdir=$(BACKEND_DIR) init
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
	@echo "\n>>> Generating accounts.json..."
	python -m infra_mgmt.python.bin.accounts $(USER_CONFIG_DIR)/config.yaml $(ACCOUNTS_CONFIG)
	@echo "\n>>> Initializing for accounts..."
	terraform -chdir=$(ACCOUNTS_DIR) init \
	  -backend-config=$(BACKEND_HCL) \
	  -backend-config="key=accounts/terraform.tfstate"

accounts-plan: 
	@echo "\n>>> Planning accounts..."
	terraform -chdir=$(ACCOUNTS_DIR) plan -var-file=$(ACCOUNTS_CONFIG)

accounts-apply: accounts-init
	@echo "\n>>> Applying accounts..."
	terraform -chdir=$(ACCOUNTS_DIR) apply -auto-approve -var-file=$(ACCOUNTS_CONFIG)
	@echo "\n>>> Fetching accounts output..."
	terraform -chdir=$(ACCOUNTS_DIR) output -json > $(ACCOUNTS_OUTPUT)
	@echo "Done!"

iam-config: 
	@echo "\n>>> Configuring IAM..."
	python -m infra_mgmt.python.bin.iam $(USER_CONFIG_DIR)/config.yaml $(ACCOUNTS_OUTPUT) $(IAM_CONFIG) $(IAM_DIR) $(IAM_MODULE)


iam-init: backend-config iam-config
	@echo "\n>>> Initializing for IAM..."
	terraform -chdir=$(IAM_DIR) init \
	  -backend-config=$(BACKEND_HCL) \
	  -backend-config="key=init_iam/terraform.tfstate"

iam-plan: 
	@echo "\n>>> Planning init-iam..."
	terraform -chdir=$(IAM_DIR) plan -var-file=$(IAM_CONFIG)

iam-apply: 
	@echo "\n>>> Applying IAM..."
	terraform -chdir=$(IAM_DIR) apply -auto-approve -var-file=$(IAM_CONFIG)
	@echo "\n>>> Fetching IAM output..."
	terraform -chdir=$(IAM_DIR) output -json > $(IAM_OUTPUT)

org-config:
	@echo "\n>>> Configuring ORG..."
	python -m infra_mgmt.python.bin.org $(USER_CONFIG_DIR)/config.yaml $(ACCOUNTS_OUTPUT) $(IAM_CONFIG) $(ORG_DIR) 

org-init:
	@echo "\n>>> Initializing org environments..."
	@mkdir -p $(LOGS_DIR)
	@for dir in $(shell find $(ORG_DIR) -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do \
		mkdir -p $(LOGS_DIR)/$$dir
		echo "\n>>> Initializing for account: $$dir..."; \
		(terraform -chdir=$(ORG_DIR)/$$dir init -no-color \
		  -backend-config=$(BACKEND_HCL) \
		  -backend-config="key=org/$$dir/terraform.tfstate" 2>&1 | tee $(LOGS_DIR)/$$dir/$$dir-init.log); \
	done

org-plan:
	@echo "\n>>> Planning org environments..."
	@for dir in $(shell find $(ORG_DIR) -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do \
		echo "\n>>> Planning for account: $$dir..."; \
		(terraform -chdir=$(ORG_DIR)/$$dir plan -no-color 2>&1 \
		  | tee $(LOGS_DIR)/$$dir/$$dir-planning.log); \
	done

org-apply:
	@echo "\n>>> Applying org environments..."
	@mkdir -p $(ORG_OUTPUT_DIR)
	@for dir in $(shell find $(ORG_DIR) -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do \
		echo "\n>>> Applying for account: $$dir..."; \
		(terraform -chdir=$(ORG_DIR)/$$dir apply -auto-approve -no-color 2>&1 \
		  | tee $(LOGS_DIR)/$$dir/$$dir-applying.log); \
		terraform -chdir=$(ORG_DIR)/$$dir output -json > $(ORG_OUTPUT_DIR)/$$dir.json
	done




