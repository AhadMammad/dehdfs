# Lab 13 — Bucketing

**Goal:** learn **bucketing** — hashing a column into a fixed number of files — the complement to the
partitioning from [labs 7–8](../lab7-hive-metastore-parquet/). Bucketing makes joins and sampling
cheaper.

## The idea

**Partitioning** splits data by a *value* (one directory per `dt`). **Bucketing** splits data by a
*hash*: `CLUSTERED BY (id) INTO 8 BUCKETS` sends each row to `hash(id) % 8`, producing exactly **8
files**. Because a value always lands in the same bucket:

- **Sampling** is cheap — read 1 of 8 files to get ~1/8 of the data (`TABLESAMPLE(BUCKET 1 OUT OF 8)`).
- **Joins** between two tables bucketed the same way can be done bucket-by-bucket, avoiding a full
  shuffle.

```
CLUSTERED BY (id) INTO 8 BUCKETS  ->  warehouse/sales_bucketed/000000_0 … 000007_0  (8 files)
```

## Run it

```bash
make up
make demo      # build a source table, a bucketed table, count the bucket files, sample one bucket
make verify    # automated PASS/FAIL checks
make beeline   # optional: interactive SQL
make clean
```

## What to look for

- `hdfs dfs -ls /user/hive/warehouse/sales_bucketed` — exactly 8 files, one per bucket.
- `SELECT count(*) … TABLESAMPLE(BUCKET 1 OUT OF 8 ON id)` returns roughly an eighth of the rows.
- `DESCRIBE FORMATTED sales_bucketed` shows `Num Buckets: 8` and the bucket column.

## What `make verify` checks

1. The **metastore is reachable**.
2. A 100k-row **source table** loads.
3. A table `CLUSTERED BY (id) INTO 8 BUCKETS` loads and is stored as **exactly 8 files** in HDFS.
4. `TABLESAMPLE(BUCKET 1 OUT OF 8)` returns **~1/8** of the rows.
