# Lab 16 — External vs Managed Tables

**Goal:** understand the single most important operational difference between Hive table types —
what `DROP TABLE` does to the **data in HDFS**.

## The idea

- A **managed** (internal) table: Hive **owns the data**. It lives under the warehouse
  (`/user/hive/warehouse/<table>`), and `DROP TABLE` deletes **both** the metadata **and** the files.
- An **external** table (`CREATE EXTERNAL TABLE … LOCATION …`): Hive owns **only the metadata**. The
  data lives wherever you point it, and `DROP TABLE` removes the schema from the metastore but
  **leaves the files untouched**.

```
DROP managed_people   ->  metastore entry gone   +  /user/hive/warehouse/managed_people  DELETED
DROP ext_people       ->  metastore entry gone   +  /data/ext/people.csv                 KEPT
```

Use external tables for data you don't want Hive to own (a shared landing zone, data written by
other tools); use managed tables for data whose lifecycle Hive should fully control.

## Run it

```bash
make up
make demo      # create one of each, then DROP both and watch what happens in HDFS
make verify    # automated PASS/FAIL checks
make beeline   # optional: interactive SQL
make clean
```

## What to look for

- `hdfs dfs -ls /user/hive/warehouse/managed_people` before/after the DROP — it disappears.
- `hdfs dfs -ls /data/ext` before/after dropping the external table — the files stay.
- `DESCRIBE FORMATTED <table>` shows `Table Type: MANAGED_TABLE` vs `EXTERNAL_TABLE`.

## What `make verify` checks

1. The **metastore is reachable**.
2. A **managed** and an **external** table are created, each with 2 rows.
3. `DROP` on the **managed** table **deletes** its HDFS data.
4. `DROP` on the **external** table **keeps** its HDFS data.
