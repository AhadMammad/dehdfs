# Lab 6 — High Availability
COMPOSE := docker compose
CLIENT  := nn1

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: ## Start the HA cluster and wait until one NameNode becomes ACTIVE
	$(COMPOSE) up -d
	@echo "==> Waiting for an ACTIVE NameNode (HA bootstrap takes a few minutes)..."
	@for i in $$(seq 1 90); do \
		s1=$$($(COMPOSE) exec -T $(CLIENT) hdfs haadmin -getServiceState nn1 2>/dev/null | tr -d '\r'); \
		s2=$$($(COMPOSE) exec -T $(CLIENT) hdfs haadmin -getServiceState nn2 2>/dev/null | tr -d '\r'); \
		echo "   nn1=$${s1:-?} nn2=$${s2:-?}"; \
		if [ "$$s1" = "active" ] || [ "$$s2" = "active" ]; then echo "==> An ACTIVE NameNode is up."; exit 0; fi; \
		sleep 4; \
	done; \
	echo "!! No active NameNode in time"; $(COMPOSE) ps; exit 1

.PHONY: down
down: ## Stop the cluster (keep volumes)
	$(COMPOSE) down

.PHONY: demo
demo: ## Run the guided walkthrough (write data, kill the active NN, watch failover)
	@bash scripts/demo.sh

.PHONY: verify
verify: ## Run automated checks (prints PASS/FAIL)
	@bash scripts/verify.sh

.PHONY: state
state: ## Print the current active/standby state of both NameNodes
	@$(COMPOSE) exec -T $(CLIENT) hdfs haadmin -getAllServiceState 2>/dev/null || true

.PHONY: ui
ui: ## Print the web UI URLs
	@echo "nn1 UI: http://localhost:9870"
	@echo "nn2 UI: http://localhost:9871"

.PHONY: shell
shell: ## Open a shell inside nn1
	$(COMPOSE) exec $(CLIENT) bash

.PHONY: logs
logs: ## Follow container logs
	$(COMPOSE) logs -f

.PHONY: clean
clean: ## Stop the cluster and delete volumes
	$(COMPOSE) down -v
