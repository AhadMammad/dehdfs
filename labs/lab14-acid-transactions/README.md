# Lab 14 — ACID Transactions

**Goal:** do `UPDATE` and `DELETE` in Hive — row-level mutations on top of **immutable** HDFS files —
using **transactional ORC** tables, **delta** files, and **compaction**.

## The idea

HDFS files can't be edited in place, so how does Hive `UPDATE`/`DELETE` a row? With **ACID tables**
it doesn't rewrite anything — it writes small **delta** files that record inserts, updates, and
deletes layered over a **base**. Reads merge the base with the deltas on the fly.

```
INSERT ...   -> delta_0000001_0000001/    (new rows)
UPDATE ...   -> delta + delete_delta       (old version tombstoned, new version added)
DELETE ...   -> delete_delta_...           (tombstone)
COMPACT major-> base_0000003/              (everything merged into a fresh base)
```

Over time deltas pile up, so a **compactor** (running in the metastore) periodically merges them:
a **minor** compaction merges deltas together; a **major** compaction merges everything into a new
base. This needs a transaction manager (`DbTxnManager`), and in Hive 2.x the table must be **ORC**,
**bucketed**, and marked `transactional=true`.

## Run it

```bash
make up
make demo      # INSERT, UPDATE, DELETE, inspect the delta files, then compact to a base
make verify    # automated PASS/FAIL checks
make beeline   # optional: interactive SQL (try SHOW COMPACTIONS)
make clean
```

## What to look for

- `hdfs dfs -ls -R /user/hive/warehouse/accounts` — `delta_*` / `delete_delta_*` dirs appear as you
  mutate, and a `base_*` dir appears after `ALTER TABLE … COMPACT 'major'`.
- `SHOW COMPACTIONS` (in `make beeline`) shows the compaction request and its state.

## What `make verify` checks

1. The **metastore is reachable**.
2. A **transactional ORC** table is created with 5 rows.
3. `UPDATE` changes a row's value.
4. `DELETE` removes a row (4 remain).
5. The mutations exist as **delta files** in HDFS.
6. **Major compaction** produces a `base_` directory, with the data unchanged.

> This is the most configuration-sensitive lab (ACID + a working compactor). If compaction is slow to
> produce a base, re-run `make verify` — the compactor runs asynchronously in the metastore.
