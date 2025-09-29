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

# Terraform config dir
CONFIG_DIR := $(TERRAFORM_DIR)/.config

# Terraform Org dirs
ORG_TF_DIR := $(TERRAFORM_DIR)//org
ORG_CONFIG_DIR := $(CONFIG_DIR)/org
ORG_CONFIG := $(ORG_CONFIG_DIR)/org.json
ORG_OUTPUT := $(ORG_CONFIG_DIR)/org_output.json

LOGS_DIR := $(TERRAFORM_DIR)/.logs

# Initial IAM user mgmt
IAM_TF_DIR := $(BUILD_DIR)/iam
IAM_CONFIG_DIR := $(CONFIG_DIR)/iam
IAM_CONFIG := $(IAM_CONFIG_DIR)/iam_users.json
IAM_OUTPUT := $(IAM_CONFIG_DIR)/iam_output.json
IAM_MODULE := $(MODULES_DIR)/iam_users_groups

# Terraform individual accounts creation mgmt
ACCOUNTS_DIR := $(BUILD_DIR)/accounts
LOGS_DIR := $(TERRAFORM_DIR)/.logs
ALL_ACCOUNT_DIRS := $(shell find $(ACCOUNTS_DIR) -mindepth 1 -maxdepth 1 -type d -not -name '.*' -exec basename {} \;)
ACCOUNTS_BUILD_OUTPUT_DIR := $(ACCOUNTS_DIR)/.output

# # Terraform org mgmt
# ORG_DIR := $(TERRAFORM_DIR)/.build/org
# ORG_BUILD_OUTPUT_DIR := $(ORG_DIR)/.output


# # Get a list of the account-specific directories in the .build/org folder
# ORG_ACCOUNT_DIRS := $(shell find $(ORG_DIR) -mindepth 1 -maxdepth 1 -type d -not -name '.*' -exec basename {} \;)


.PHONY: all show-paths bootstrap backend-init backend-config accounts org

# Default target
all: bootstrap backend-config accounts org

show-paths:
	@echo "Makefile dir: $(MAKEFILE_DIR)"
	@echo "Bootstrap dir: $(BACKEND_DIR)"

# Step 1: Apply bootstrap (creates S3 + DynamoDB backend infra)
bootstrap:
	@echo "\n>>> Generating backend terraform.tfvars..."
	python -m infra_mgmt.python.bin.backend $(USER_CONFIG_DIR) $(MODULES_DIR) $(BACKEND_DIR)
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


org-init: backend-config
	@echo "\n>>> Generating org.json..."
	@mkdir -p $(ORG_CONFIG_DIR)
	python -m infra_mgmt.python.bin.org_generate_accounts $(USER_CONFIG_DIR) $(MODULES_DIR) $(ORG_CONFIG) $(ORG_TF_DIR)
	@echo "\n>>> Initializing Terraform for ORG..."
	terraform -chdir=$(ORG_TF_DIR) init \
	  -backend-config=$(BACKEND_HCL) \
	  -backend-config="key=accounts/terraform.tfstate"


org-plan: 
	@echo "\n>>> Planning ORG..."
	terraform -chdir=$(ORG_TF_DIR) plan -var-file=$(ORG_CONFIG)



org-apply: org-init
	@echo "\n>>> Applying ORG..."
	terraform -chdir=$(ORG_TF_DIR) apply -var-file=$(ORG_CONFIG)
	@echo "\n>>> Fetching ORG output..."
	terraform -chdir=$(ORG_TF_DIR) output -json > $(ORG_OUTPUT)
	@echo "Done!"



iam-config: 
	@echo "\n>>> Configuring INIT-IAM..."
	@mkdir -p $(IAM_TF_DIR)
	python -m infra_mgmt.python.bin.iam $(USER_CONFIG_DIR) $(MODULES_DIR) $(ORG_OUTPUT) $(IAM_CONFIG) $(IAM_TF_DIR) $(IAM_MODULE)



iam-init: backend-config iam-config
	@echo "\n>>> Initializing for INIT-IAM..."
	terraform -chdir=$(IAM_TF_DIR) init \
	  -backend-config=$(BACKEND_HCL) \
	  -backend-config="key=init_iam/terraform.tfstate"



iam-plan: 
	@echo "\n>>> Planning INIT-IAM..."
	terraform -chdir=$(IAM_TF_DIR) plan -var-file=$(IAM_CONFIG)



iam-apply: 
	@echo "\n>>> Applying INIT-IAM..."
	terraform -chdir=$(IAM_TF_DIR) apply -var-file=$(IAM_CONFIG)
	@echo "\n>>> Fetching INIT-IAM output..."
	terraform -chdir=$(IAM_TF_DIR) output -json > $(IAM_OUTPUT)


accounts-config:
	@echo "\n>>> Configuring Individual Accounts..."
	python -m infra_mgmt.python.bin.accounts $(USER_CONFIG_DIR) $(MODULES_DIR) $(ORG_OUTPUT) $(ACCOUNTS_DIR) $(IAM_CONFIG)


accounts-init:
	@echo "\n>>> Initializing Individual Accounts..."
	@mkdir -p $(LOGS_DIR)
	@for dir in $(ALL_ACCOUNT_DIRS); do \
		mkdir -p $(LOGS_DIR)/$$dir; \
		echo "\n>>> Initializing for account: $$dir..."; \
		(terraform -chdir=$(ACCOUNTS_DIR)/$$dir init -no-color \
		  -backend-config=$(BACKEND_HCL) \
		  -backend-config="key=org/$$dir/terraform.tfstate" 2>&1 | tee $(LOGS_DIR)/$$dir/$$dir-init.log); \
	done

#################### REFACTOR: GOOD TO THIS POINT ###################

accounts-plan:
	@echo "\n>>> Planning for Individual Accounts..."
	@for dir in $(ALL_ACCOUNT_DIRS); do \
		echo "\n>>> Planning for account: $$dir..."; \
		(terraform -chdir=$(ACCOUNTS_DIR)/$$dir plan -no-color 2>&1 \
		  | tee $(LOGS_DIR)/$$dir/$$dir-planning.log); \
	done

accounts-apply:
	@echo "\n>>> Applying Individual Accounts..."
	@mkdir -p $(ACCOUNTS_BUILD_OUTPUT_DIR)
	@for dir in $(ALL_ACCOUNT_DIRS); do \
		echo "\n>>> Applying for account: $$dir..."; \
		(terraform -chdir=$(ACCOUNTS_DIR)/$$dir apply -no-color 2>&1 \
		  | tee $(LOGS_DIR)/$$dir/$$dir-applying.log); \
		echo "\n>>> Fetching outputs for account: $$dir..."; \
		terraform -chdir=$(ACCOUNTS_DIR)/$$dir output -json > $(ACCOUNTS_BUILD_OUTPUT_DIR)/$$dir.json; \
		break; \
	done
# break; \

# org-destroy:
# 	@echo "\n>>> Destroying org environments..."
# 	@for dir in $(ORG_ACCOUNT_DIRS); do \
# 		echo "\n>>> Destroying for account: $$dir..."; \
# 		(terraform -chdir=$(ORG_DIR)/$$dir destroy -no-color 2>&1 \
# 		  | tee $(LOGS_DIR)/$$dir/$$dir-destroying.log); \
# 	done

# iam-destroy: 
# 	@echo "\n>>> Destroying IAM..."
# 	terraform -chdir=$(IAM_DIR) destroy -var-file=$(IAM_CONFIG)

# accounts-destroy: accounts-init
# 	@echo "\n>>> Destroying accounts..."
# 	terraform -chdir=$(ACCOUNTS_DIR) destroy -var-file=$(ACCOUNTS_CONFIG)
# 	@echo "Done!"


# Step 6 (Option A): Generate VPN config for a single user
.PHONY: vpn-config
vpn-config:
	@if [ -z "$(account)" ]; then \
		echo "ERROR: 'account' argument is required."; \
		echo "Usage: make vpn-config account=<account_alias> user=<user_name>"; \
		exit 1; \
	f
	@if [ -z "$(user)" ]; then \
		echo "ERROR: 'user' argument is required."; \
		echo "Usage: make vpn-config account=<account_alias> user=<user_name>"; \
		exit 1; \
	f

	ACCOUNT_ALIAS=$(account); \
	USER_NAME=$(user); \
	ACCOUNT_DIR=$(ACCOUNTS_DIR)/$(ACCOUNT_ALIAS); \
	CERT_DIR=$(TERRAFORM_DIR)/.client_vpn_configs/$(ACCOUNT_ALIAS); \
	USER_CERT_PATH=$(CERT_DIR)/$(USER_NAME).crt; \
	USER_KEY_PATH=$(CERT_DIR)/$(USER_NAME).key; \
	OUTPUT_DIR=generated_vpn_configs/$(ACCOUNT_ALIAS); \
	OVPN_FILE=$(OUTPUT_DIR)/$(USER_NAME).ovpn; \
	AWS_PROFILE=pulse-infra-admin; \
	AWS_REGION=us-west-2; \
	\
	echo "\n>>> Generating VPN config for user '$${USER_NAME}' in account '$${ACCOUNT_ALIAS}'..."; \
	\
	if [ ! -f "$${USER_CERT_PATH}" ] || [ ! -f "$${USER_KEY_PATH}" ]; then \
		echo "ERROR: Certificate or key file not found for user '$${USER_NAME}' in account '$${ACCOUNT_ALIAS}'."; \
		echo "Searched for: $${USER_CERT_PATH} and $${USER_KEY_PATH}"; \
		echo "Please ensure 'make accounts-apply' has been run successfully and the user has 'vpn_access: true'."; \
		exit 1; \
	f; \
	\
	mkdir -p $${OUTPUT_DIR}; \
	\
	echo "--> Fetching VPN Endpoint ID from Terraform state..."; \
	VPN_ENDPOINT_ID=$$(terraform -chdir=$${ACCOUNT_DIR} output -raw client_vpn_endpoint_id); \
	if [ -z "$$VPN_ENDPOINT_ID" ]; then \
		echo "ERROR: Could not fetch VPN Endpoint ID for account '$${ACCOUNT_ALIAS}'."; \
		exit 1; \
	f; \
	\
	echo "--> Downloading base VPN configuration from AWS..."; \
	aws ec2 export-client-vpn-client-configuration \
		--client-vpn-endpoint-id $$VPN_ENDPOINT_ID \
		--profile $${AWS_PROFILE} \
		--region $${AWS_REGION} \
		--output text > $${OVPN_FILE}; \
	\
	echo "--> Appending user certificate and key to configuration..."; \
	printf '\n<cert>\n' >> $${OVPN_FILE}; \
	cat $${USER_CERT_PATH} >> $${OVPN_FILE}; \
	printf '\n</cert>\n' >> $${OVPN_FILE}; \
	\
	printf '\n<key>\n' >> $${OVPN_FILE}; \
	cat $${USER_KEY_PATH} >> $${OVPN_FILE}; \
	printf '\n</key>\n' >> $${OVPN_FILE}; \
	\
	echo "\n>>> Success!"; \
	echo "VPN configuration file created at: $${OVPN_FILE}"; \
	echo "Please distribute this file securely to the user."

# Step 6 (Option B): Generate VPN configs for ALL users with generated certs
.PHONY: vpn-configs-all
vpn-configs-all:
	@echo "\n>>> Generating all possible VPN configuration files..."
	GENERATED_VPN_DIR=generated_vpn_configs; \
	mkdir -p $$GENERATED_VPN_DIR; \
	AWS_PROFILE=pulse-infra-admin; \
	AWS_REGION=us-west-2; \
	ROLE_NAME=OrganizationAccountAccessRole; \
	\
	for key_file in $$(find $(TERRAFORM_DIR)/.client_vpn_configs -name "*.key"); do \
		USER_NAME=$$(basename $$key_file .key); \
		ACCOUNT_ALIAS=$$(basename $$(dirname $$key_file)); \
		ACCOUNT_DIR=$(ACCOUNTS_DIR)/$$ACCOUNT_ALIAS; \
		USER_CERT_PATH=$$(dirname $$key_file)/$$USER_NAME.crt; \
		OUTPUT_DIR=$$GENERATED_VPN_DIR/$$ACCOUNT_ALIAS; \
		OVPN_FILE=$$OUTPUT_DIR/$$USER_NAME.ovpn; \
		\
		echo "\n--> Found cert for user '$$USER_NAME' in account '$$ACCOUNT_ALIAS'. Generating config..."; \
		mkdir -p $$OUTPUT_DIR; \
		\
		ACCOUNT_ID=$$(terraform -chdir=$$ACCOUNT_DIR output -raw target_account_id); \
		VPN_ENDPOINT_ID=$$(terraform -chdir=$$ACCOUNT_DIR output -raw client_vpn_endpoint_id); \
		\
		if [ -z "$$VPN_ENDPOINT_ID" ] || [ -z "$$ACCOUNT_ID" ]; then \
			echo "ERROR: Could not fetch required outputs for account '$$ACCOUNT_ALIAS'. Skipping."; \
			echo "         (Have you run 'make accounts-apply' since the last configuration change?)"; \
			continue; \
		fi; \
		\
		ROLE_ARN="arn:aws:iam::$$ACCOUNT_ID:role/$$ROLE_NAME"; \
		\
		echo "--> Assuming role $$ROLE_ARN..."; \
		CREDS=$$(aws sts assume-role --role-arn $$ROLE_ARN --role-session-name "VPNConfigGen" --profile $$AWS_PROFILE --region $$AWS_REGION --output json); \
		\
		if [ -z "$$CREDS" ]; then \
			echo "ERROR: Failed to assume role for account '$$ACCOUNT_ALIAS'. Skipping."; \
			continue; \
		fi; \
		\
		export AWS_ACCESS_KEY_ID=$$(echo $$CREDS | jq -r .Credentials.AccessKeyId); \
		export AWS_SECRET_ACCESS_KEY=$$(echo $$CREDS | jq -r .Credentials.SecretAccessKey); \
		export AWS_SESSION_TOKEN=$$(echo $$CREDS | jq -r .Credentials.SessionToken); \
		\
		echo "--> Downloading base VPN configuration from AWS..."; \
		aws ec2 export-client-vpn-client-configuration \
			--client-vpn-endpoint-id $$VPN_ENDPOINT_ID \
			--region $$AWS_REGION \
			--output text > $$OVPN_FILE; \
		\
		unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; \
		\
		echo "--> Appending user certificate and key to configuration..."; \
		printf '\n<cert>\n' >> $$OVPN_FILE; \
		cat $$USER_CERT_PATH >> $$OVPN_FILE; \
		printf '\n</cert>\n' >> $$OVPN_FILE; \
		\
		printf '\n<key>\n' >> $$OVPN_FILE; \
		cat $$key_file >> $$OVPN_FILE; \
		printf '\n</key>\n' >> $$OVPN_FILE; \
	done; \
	\
	@echo "\n>>> Success!"; \
	echo "All available VPN configuration files have been created in: $$GENERATED_VPN_DIR"