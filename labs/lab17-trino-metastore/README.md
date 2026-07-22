# Lab 17 — Trino over the Hive Metastore

**Goal:** query the **same** Hive tables from HDFS with **Trino** — a fast, distributed SQL engine
that uses the metastore for schema but runs **no MapReduce**. It makes the point that the **engine**
is separate from the **storage**.

## The idea

Labs 7–8 showed Hive running SQL as MapReduce (local, then on YARN). But the tables are just Parquet
files in HDFS plus metadata in the metastore — so **any** engine that speaks to the metastore can
read them. **Trino** does exactly that: it points at `thrift://hive-metastore:9083`, reads the same
`hdfs://…/warehouse/…` files, and executes queries in its own in-memory, massively-parallel engine —
typically **interactive** latency instead of minute-scale MapReduce.

```
                 ┌─ Hive (MapReduce)  ─┐
metastore + HDFS ─┤                     ├─ same tables, same files
                 └─ Trino (MPP, :8080) ─┘
```

## Run it

```bash
make up        # HDFS + metastore + HiveServer2 + Trino
make demo      # build a Parquet table with Hive, then query it with Trino
make verify    # automated PASS/FAIL checks
make trino     # optional: interactive Trino CLI (try: SHOW TABLES;)
make ui        # Trino UI at http://localhost:8080
make clean
```

## What to look for

- The **Trino UI** at http://localhost:8080 shows each query, its stages, and how long it took.
- `SHOW TABLES` in Trino lists the same tables Hive created — they share the metastore.
- Trino's `count(*)`/`GROUP BY` match Hive's, because both read the identical HDFS files.

## What `make verify` checks

1. **Trino is up** and answers `SELECT 1`.
2. **Hive** builds a 100k-row Parquet table.
3. **Trino sees** that table through the shared metastore (`SHOW TABLES`).
4. Trino's **`count(*)` matches** Hive's (same files, different engine).
5. A Trino **`GROUP BY`** returns the 5 countries.

> Uses `trinodb/trino:398`. Trino is version-sensitive about connector/HDFS config; if a query fails
> to reach HDFS, check `docker compose logs trino` and adjust `config/catalog/hive.properties`.
