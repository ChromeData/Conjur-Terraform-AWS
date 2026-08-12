.PHONY: help up down policy secrets init plan apply apply-datasource verify prove-leak destroy clean

TF     := terraform -chdir=terraform
SUMMON := summon -p summon-conjur -f summon/secrets.yml

help:
	@echo "up               start Conjur (docker compose)"
	@echo "policy           load the Conjur policy"
	@echo "secrets          store AWS credentials in Conjur"
	@echo ""
	@echo "apply            provision AWS via Summon  (correct path - no state leak)"
	@echo "apply-datasource provision AWS via conjur_secret data source (leaks - the demo)"
	@echo "verify           scan state for credential material"
	@echo "prove-leak       run BOTH paths and diff the result. This is the lab."
	@echo ""
	@echo "destroy          tear down AWS"
	@echo "down             stop Conjur"

# ---------------------------------------------------------------------------
# Conjur
# ---------------------------------------------------------------------------
up:
	docker compose up -d
	@echo "waiting for Conjur to come up..."
	@for i in $$(seq 1 30); do \
	  if docker compose exec -T client conjur whoami >/dev/null 2>&1; then echo "  ready"; exit 0; fi; \
	  sleep 2; \
	done; echo "  timed out - check 'docker compose logs conjur'"; exit 1

policy:
	./scripts/load-policy.sh

secrets:
	./scripts/set-secrets.sh

down:
	docker compose down -v

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------
init:
	$(TF) init

plan: init
	$(SUMMON) $(TF) plan

# The correct path. Summon injects the credentials into the environment of this
# one process; Terraform reads them from the standard AWS chain and never holds
# them as a value.
apply: init
	$(SUMMON) $(TF) apply -auto-approve -var credential_source=summon

# The intuitive path, kept so the leak can be measured.
apply-datasource: init
	$(TF) apply -auto-approve -var credential_source=datasource

verify:
	./scripts/verify-no-secrets-in-state.sh

# ---------------------------------------------------------------------------
# The demonstration
#
# Build with data sources, prove it leaks, tear down, rebuild with Summon,
# prove it does not. Two runs, one measurable difference.
# ---------------------------------------------------------------------------
prove-leak:
	@echo "=========================================================="
	@echo " PATH 1/2 - conjur_secret data source (expected to leak)"
	@echo "=========================================================="
	@$(MAKE) apply-datasource
	@./scripts/verify-no-secrets-in-state.sh > /tmp/lab01-datasource.txt 2>&1 || true
	@cat /tmp/lab01-datasource.txt
	@echo ""
	@echo "=========================================================="
	@echo " Tearing down and rebuilding via Summon"
	@echo "=========================================================="
	@$(TF) destroy -auto-approve -var credential_source=datasource
	@rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup
	@$(MAKE) apply
	@./scripts/verify-no-secrets-in-state.sh > /tmp/lab01-summon.txt 2>&1 || true
	@cat /tmp/lab01-summon.txt
	@echo ""
	@echo "=========================================================="
	@echo " DIFFERENCE"
	@echo "=========================================================="
	@diff /tmp/lab01-datasource.txt /tmp/lab01-summon.txt || true
	@echo ""
	@echo "Put both outputs in findings/ and the character counts in LAB-NOTES.md."

destroy:
	$(SUMMON) $(TF) destroy -auto-approve

clean: destroy down
	rm -rf terraform/.terraform terraform/terraform.tfstate*
