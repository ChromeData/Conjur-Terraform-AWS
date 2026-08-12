.PHONY: help datakey up policy secrets plan apply verify destroy clean
.DEFAULT_GOAL := help

COMPOSE := docker compose
CONJUR  := $(COMPOSE) exec -T client conjur
TF      := terraform -chdir=terraform

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

datakey: ## Generate a Conjur data key into .env (run once)
	@test -f .env && { echo ".env exists — refusing to overwrite. rm it first."; exit 1; } || true
	@echo "CONJUR_DATA_KEY=$$($(COMPOSE) run --no-deps --rm conjur data-key generate | tr -d '\r')" > .env
	@echo "Wrote .env. This file is gitignored and must stay that way."

up: ## Start Conjur + Postgres, initialise the lab account
	$(COMPOSE) up -d
	@echo "Waiting for Conjur to report healthy..."
	@until [ "$$($(COMPOSE) ps -q conjur | xargs docker inspect -f '{{.State.Health.Status}}')" = "healthy" ]; do sleep 3; done
	@$(COMPOSE) exec -T conjur conjurctl account create lab > .conjur-admin-key 2>/dev/null || \
		echo "Account 'lab' already exists — skipping create."
	@echo "Admin API key written to .conjur-admin-key (gitignored)."

policy: ## Load policy tree. Emits the runner API key ONCE.
	@./scripts/load-policy.sh

secrets: ## Populate aws-credentials/* from your throwaway IAM user
	@./scripts/set-secrets.sh

plan: ## terraform plan, credentials pulled from Conjur
	$(TF) init -upgrade
	$(TF) plan

apply: ## terraform apply
	$(TF) apply

verify: ## Assert no AWS credentials landed in state
	@./scripts/verify-no-secrets-in-state.sh

destroy: ## Tear down AWS resources, then the Conjur stack
	-$(TF) destroy -auto-approve
	$(COMPOSE) down -v
	@echo "Down. Volume removed — next 'make up' starts clean."

clean: destroy ## destroy + remove local key material
	rm -f .env .conjur-admin-key .conjur-runner-key
	rm -rf terraform/.terraform terraform/terraform.tfstate*
