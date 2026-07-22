# Lab 14 — ACID transactions
COMPOSE := docker compose
NN      := namenode
HS      := hive-server

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: ## Start the cluster and wait until all containers report healthy
	$(COMPOSE) up -d
	@echo "==> Waiting for containers to report healthy (HDFS + metastore + HiveServer2)..."
	@for i in $$(seq 1 100); do \
		cids=$$($(COMPOSE) ps -q); \
		if [ -n "$$cids" ] && [ "$$(echo "$$cids" | xargs docker inspect -f '{{.State.Health.Status}}' 2>/dev/null | grep -vc healthy)" = "0" ]; then \
			echo "==> Cluster is healthy."; exit 0; \
		fi; \
		sleep 5; \
	done; \
	echo "!! containers not healthy in time"; $(COMPOSE) ps; exit 1

.PHONY: down
down: ## Stop the cluster (keep volumes)
	$(COMPOSE) down

.PHONY: demo
demo: ## Run the guided walkthrough (INSERT/UPDATE/DELETE + compaction)
	@bash scripts/demo.sh

.PHONY: verify
verify: ## Run automated checks (prints PASS/FAIL)
	@bash scripts/verify.sh

.PHONY: beeline
beeline: ## Open an interactive Beeline SQL shell on HiveServer2
	$(COMPOSE) exec $(HS) beeline -u jdbc:hive2://localhost:10000 -n root

.PHONY: ui
ui: ## Print the web UI URLs
	@echo "NameNode UI:    http://localhost:9870"
	@echo "HiveServer2 UI: http://localhost:10002"

.PHONY: shell
shell: ## Open a shell inside the NameNode container
	$(COMPOSE) exec $(NN) bash

.PHONY: logs
logs: ## Follow container logs
	$(COMPOSE) logs -f

.PHONY: clean
clean: ## Stop the cluster and delete volumes
	$(COMPOSE) down -v
