# dehdfs — root Makefile. Orchestrates the eighteen labs.
# Individual labs live in labs/*/ and each has its own Makefile with the same targets.

LABS := lab1-cluster-basics \
        lab2-blocks-replication \
        lab3-datanode-failure \
        lab4-namenode-metadata \
        lab5-webhdfs-quotas-trash \
        lab6-high-availability \
        lab7-hive-metastore-parquet \
        lab8-yarn-hive-jobs \
        lab9-erasure-coding \
        lab10-snapshots \
        lab11-permissions-acls \
        lab12-rack-awareness \
        lab13-bucketing \
        lab14-acid-transactions \
        lab15-formats-schema-evolution \
        lab16-external-vs-managed \
        lab17-trino-metastore \
        lab18-spark-sql

DOCS := $(abspath docs/index.html)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@echo "dehdfs — HDFS learning labs"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Labs (cd into each and use the same targets: up/demo/verify/clean):"
	@for l in $(LABS); do echo "  labs/$$l"; done

.PHONY: docs
docs: ## Print the path to the offline HTML explainer
	@echo "Open this file in your browser:"
	@echo "  $(DOCS)"
	@# Best-effort auto-open (ignored if the opener is unavailable)
	@command -v open >/dev/null 2>&1 && open "$(DOCS)" || true

.PHONY: verify-all
verify-all: ## Run every lab in sequence: up -> verify -> clean, then summarise
	@echo "==> Running all labs. This starts and tears down each cluster in turn."
	@failed=""; \
	for l in $(LABS); do \
		echo ""; echo "================ $$l ================"; \
		if $(MAKE) -C labs/$$l up verify; then \
			echo "---- $$l: PASS ----"; \
		else \
			echo "---- $$l: FAIL ----"; \
			failed="$$failed $$l"; \
		fi; \
		$(MAKE) -C labs/$$l clean >/dev/null 2>&1 || true; \
	done; \
	echo ""; echo "================ SUMMARY ================"; \
	if [ -z "$$failed" ]; then \
		echo "ALL LABS PASSED"; \
	else \
		echo "FAILED LABS:$$failed"; \
		exit 1; \
	fi

.PHONY: clean-all
clean-all: ## Tear down every lab (stop containers + delete volumes)
	@for l in $(LABS); do \
		echo "==> cleaning labs/$$l"; \
		$(MAKE) -C labs/$$l clean >/dev/null 2>&1 || true; \
	done
	@echo "All labs cleaned."
