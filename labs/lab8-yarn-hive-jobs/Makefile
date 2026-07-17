# Lab 8 — the same Parquet write as Lab 7, executed on YARN
COMPOSE := docker compose
NN      := namenode
HS      := hive-server
RM      := resourcemanager

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: ## Start HDFS + YARN + the metastore/HiveServer2 and wait until all report healthy
	$(COMPOSE) up -d
	@echo "==> Waiting for containers to report healthy (HDFS + YARN + metastore + HiveServer2)..."
	@for i in $$(seq 1 120); do \
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
demo: ## Run the guided walkthrough (write Parquet as a YARN job; watch it at :8088)
	@bash scripts/demo.sh

.PHONY: verify
verify: ## Run automated checks (prints PASS/FAIL)
	@bash scripts/verify.sh

.PHONY: apps
apps: ## List YARN applications (submitted/running/finished)
	$(COMPOSE) exec $(RM) yarn application -list -appStates ALL

.PHONY: beeline
beeline: ## Open an interactive Beeline SQL shell on HiveServer2
	$(COMPOSE) exec $(HS) beeline -u jdbc:hive2://localhost:10000 -n root

.PHONY: metastore
metastore: ## Show what the Hive Metastore persists in PostgreSQL (schemas, tables, partitions)
	@bash scripts/metastore.sh

.PHONY: ui
ui: ## Print the web UI URLs
	@echo "Hue SQL editor:  http://localhost:8888  (create any admin user on first visit)"
	@echo "NameNode UI:     http://localhost:9870"
	@echo "YARN RM UI:      http://localhost:8088"
	@echo "JobHistory UI:   http://localhost:8188"
	@echo "HiveServer2 UI:  http://localhost:10002"

.PHONY: shell
shell: ## Open a shell inside the ResourceManager container
	$(COMPOSE) exec $(RM) bash

.PHONY: logs
logs: ## Follow container logs
	$(COMPOSE) logs -f

.PHONY: clean
clean: ## Stop the cluster and delete volumes
	$(COMPOSE) down -v
