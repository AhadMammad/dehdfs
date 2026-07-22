# Lab 15 — Formats & Schema Evolution

**Goal:** go beyond Parquet/ORC — add **Avro**, compare **compression codecs**, and **evolve a
schema** (add a column) without rewriting the data already on disk.

## The ideas

### Avro vs Parquet/ORC
**Avro** is **row-oriented** and carries its **schema inside every file** — great for streaming and
record-at-a-time writes, where Parquet/ORC are columnar and better for analytics scans. You can spot
an Avro file by its magic bytes: it begins with `Obj`.

### Compression codecs
The same columnar data can be compressed with different codecs. **SNAPPY** is fast but larger;
**GZIP** is slower but squeezes harder. Setting `TBLPROPERTIES ('parquet.compression'='GZIP')` vs
`'SNAPPY'` and comparing `hdfs dfs -du -s` shows the trade-off directly.

### Schema evolution
`ALTER TABLE … ADD COLUMNS (note STRING)` changes only the **metastore schema**. The files already
written are **not** rewritten — old rows simply read back `NULL` for the new column. That's why
columnar/Avro formats are said to support **schema evolution**.

## Run it

```bash
make up
make demo      # write Avro, compare gzip vs snappy sizes, add a column and read old data
make verify    # automated PASS/FAIL checks
make beeline   # optional: interactive SQL
make clean
```

## What to look for

- `hdfs dfs -cat <avro file> | head -c 3` → `Obj`.
- `hdfs dfs -du -s -v .../sales_snappy .../sales_gzip` — gzip is smaller.
- After `ADD COLUMNS (note STRING)`, `SELECT id, note …` shows `NULL` for pre-existing rows.

## What `make verify` checks

1. The **metastore is reachable** and a source table loads.
2. An **Avro** table round-trips and its files start with the `Obj` magic.
3. **GZIP** stores fewer bytes than **SNAPPY** for the same Parquet data.
4. **Schema evolution**: after `ADD COLUMNS`, all existing rows read `NULL` for the new column (no
   rewrite).
