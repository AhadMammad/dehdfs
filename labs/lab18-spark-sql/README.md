# Lab 18 — Spark SQL over the Hive Metastore

**Goal:** use **Spark SQL** as the compute engine over the **same** Hive warehouse on HDFS — read
Hive's tables, and write one back that Hive can read. Another proof that **engine ≠ storage**.

## The idea

Spark is a modern, in-memory distributed engine. Point it at the shared Hive metastore
(`spark.sql.catalogImplementation=hive`, `hive.metastore.uris=thrift://hive-metastore:9083`) and it
sees exactly the tables Hive created, reading their Parquet/ORC files straight from HDFS — no
MapReduce, no YARN. Because both engines use the **same metastore and the same HDFS files**, a table
written by one is immediately visible to the other.

```
                 ┌─ Hive  (MapReduce)  ─┐
metastore + HDFS ─┤                      ├─ same tables; write with one, read with the other
                 └─ Spark (Spark SQL)   ─┘
```

## Run it

```bash
make up          # HDFS + metastore + HiveServer2 + Spark
make demo        # Spark reads Hive's Parquet table, then writes one Hive reads back
make verify      # automated PASS/FAIL checks
make spark-sql   # optional: interactive Spark SQL shell
make clean
```

## What to look for

- `SHOW TABLES` in `make spark-sql` lists the same tables Hive made — one shared catalog.
- Spark's `count(*)` / `GROUP BY` match Hive's, because both read the identical HDFS files.
- A `CREATE TABLE … AS SELECT` run in Spark appears in Hive (`make beeline`) with no extra steps.

## What `make verify` checks

1. **Spark SQL is up** and answers a query.
2. **Hive** builds a 100k-row Parquet table.
3. **Spark reads** that table and its `count(*)` matches Hive's.
4. **Spark writes** a summary table that **Hive reads back** (5 country rows).

> Uses `apache/spark:3.3.2` (its bundled Hive 2.3 metastore client matches this metastore). Spark is
> version-sensitive; if the metastore handshake fails, check `docker compose logs spark` and adjust
> `config/spark-defaults.conf` (e.g. `spark.sql.hive.metastore.version`).
