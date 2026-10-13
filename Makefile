SHELL := /bin/bash

TF_DIRS        := bootstrap terraform/environments/dev
TF_MODULE_DIRS := terraform/modules/network terraform/modules/data terraform/modules/lab terraform/modules/api terraform/modules/frontend terraform/modules/governance
PROJECT        ?= osq
REGION         ?= us-east-1
# Prefer the local venv (holds boto3 + pytest) when it exists.
PYTHON         ?= $(shell test -x .venv/bin/python && echo .venv/bin/python || echo python3)
TABLE_PREFIX   ?= $(PROJECT)-dev
USERS_TABLE    ?= $(TABLE_PREFIX)-users
LABS_TABLE     ?= $(TABLE_PREFIX)-labs
# Read from dev state when available; override for CI or a second environment.
FRONTEND_BUCKET       ?= $(shell terraform -chdir=terraform/environments/dev output -raw frontend_bucket_name 2>/dev/null)
FRONTEND_DISTRIBUTION ?= $(shell terraform -chdir=terraform/environments/dev output -raw frontend_distribution_id 2>/dev/null)

.DEFAULT_GOAL := help

.PHONY: help fmt fmt-check validate tflint lint bootstrap init-dev plan-dev apply-dev destroy-dev test test-policies test-backend test-frontend test-terraform seed-users seed-labs deploy-frontend serve cost clean security

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

fmt: ## Format all Terraform files
	terraform fmt -recursive

fmt-check: ## Fail if Terraform files are not formatted
	terraform fmt -check -recursive

validate: ## Validate every Terraform directory (no AWS credentials required)
	@for d in $(TF_DIRS) $(TF_MODULE_DIRS); do \
		echo "==> $$d"; \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null; \
		terraform -chdir=$$d validate; \
	done

tflint: ## Run tflint across the repository
	tflint --init
	tflint --recursive

lint: fmt-check validate tflint ## Full local lint (fmt + validate + tflint)

test: test-backend test-policies test-frontend test-terraform ## Everything that can run without AWS credentials

bootstrap: ## Create state backend, KMS key, SNS topic and budget in the current account
	terraform -chdir=bootstrap init -input=false
	terraform -chdir=bootstrap apply -input=false
	@echo ""
	@echo "Paste this into terraform/environments/dev/backend.hcl:"
	@terraform -chdir=bootstrap output -raw backend_hcl

init-dev: ## Initialize the dev environment with its S3 backend
	@test -f terraform/environments/dev/backend.hcl || { echo "missing terraform/environments/dev/backend.hcl - run: cp terraform/environments/dev/backend.hcl.example terraform/environments/dev/backend.hcl"; exit 1; }
	terraform -chdir=terraform/environments/dev init -input=false -backend-config=backend.hcl

plan-dev: ## Plan the dev environment
	terraform -chdir=terraform/environments/dev plan -input=false -out=tfplan

apply-dev: ## Apply the last saved dev plan
	terraform -chdir=terraform/environments/dev apply -input=false tfplan

destroy-dev: ## Destroy everything the dev environment manages
	terraform -chdir=terraform/environments/dev destroy -input=false

test-policies: ## Run Rego unit tests and assert on every policy fixture
	conftest verify --policy policies/opa
	@echo "==> fixture: private SSH must pass"
	conftest test policies/tests/fixtures/plan_private_ssh.json --policy policies/opa
	@echo "==> fixture: public SSH must be denied"
	@if conftest test policies/tests/fixtures/plan_public_ssh.json --policy policies/opa >/dev/null 2>&1; then \
		echo "FAIL: public SSH plan was not denied"; exit 1; \
	else echo "OK: public SSH denied"; fi
	@echo "==> fixture: oversized instance must be denied"
	@if conftest test policies/tests/fixtures/plan_oversized_instance.json --policy policies/opa >/dev/null 2>&1; then \
		echo "FAIL: oversized instance plan was not denied"; exit 1; \
	else echo "OK: oversized instance denied"; fi
	@echo "==> fixture: active CloudTrail must pass (GOV-001)"
	conftest test policies/tests/fixtures/plan_trail_ok.json --policy policies/opa
	@echo "==> fixture: disabled CloudTrail must be denied (GOV-001)"
	@if conftest test policies/tests/fixtures/plan_trail_disabled.json --policy policies/opa >/dev/null 2>&1; then \
		echo "FAIL: disabled trail plan was not denied"; exit 1; \
	else echo "OK: disabled trail denied"; fi

test-backend: ## Run the Python backend unit tests
	$(PYTHON) -m pytest tests/ -q

test-frontend: ## Check frontend syntax and run the mock API smoke test
	@command -v node >/dev/null 2>&1 || { echo 'node is required for test-frontend'; exit 1; }
	node --check frontend/api.js
	node --check frontend/app.js
	node frontend/smoke.test.js

test-terraform: ## Run the module tests (mocked provider, no AWS credentials needed)
	@for d in $(TF_MODULE_DIRS); do \
		echo "==> $$d"; \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null; \
		terraform -chdir=$$d test; \
	done

seed-users: ## Mint learner tokens (printed once, only the hash is stored)
	$(PYTHON) scripts/seed_users.py --users-table $(USERS_TABLE) --region $(REGION)

seed-labs: ## Load the lab catalog, including the flags the API redacts
	$(PYTHON) scripts/seed_labs.py --labs-table $(LABS_TABLE) --region $(REGION)

deploy-frontend: ## Sync the web UI to the private S3 bucket and invalidate CloudFront
	@test -n "$(FRONTEND_BUCKET)" || { echo "FRONTEND_BUCKET is empty. Run: terraform -chdir=terraform/environments/dev output frontend_bucket_name"; exit 1; }
	# Assets: short max-age, because nothing is content-hashed yet.
	aws s3 sync frontend/ s3://$(FRONTEND_BUCKET) --delete \
		--exclude "index.html" --exclude "smoke.test.js" \
		--cache-control "public, max-age=300"
	# Shell: always revalidate so a deploy is visible on the next refresh.
	aws s3 cp frontend/index.html s3://$(FRONTEND_BUCKET)/index.html \
		--cache-control "no-cache" --content-type "text/html; charset=utf-8"
	@if test -n "$(FRONTEND_DISTRIBUTION)"; then \
		echo "==> invalidating $(FRONTEND_DISTRIBUTION)"; \
		aws cloudfront create-invalidation --distribution-id $(FRONTEND_DISTRIBUTION) --paths "/*" >/dev/null; \
	else \
		echo "skip invalidation: FRONTEND_DISTRIBUTION is empty"; \
	fi

serve: ## Serve the frontend locally at http://localhost:8080
	@echo "Frontend: http://localhost:8080"
	python3 -m http.server 8080 --directory frontend

cost: ## Show the last 7 days of cost for the current account
	aws ce get-cost-and-usage \
		--time-period Start=$$(date -d '-7 days' +%Y-%m-%d),End=$$(date +%Y-%m-%d) \
		--granularity DAILY \
		--metrics UnblendedCost

clean: ## Remove local Terraform working directories and saved plans
	find . -type d -name .terraform -prune -exec rm -rf {} +
	find . -type f -name tfplan -delete

security: ## Run Checkov and TruffleHog locally
	checkov -d . --framework terraform --quiet
	trufflehog git file://. --results=verified,unknown --fail
