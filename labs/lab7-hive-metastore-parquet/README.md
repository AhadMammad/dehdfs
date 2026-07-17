# Lab 7 — Hive Metastore, Storage Formats & Partitioning

**Goal:** see what a *table* really is on top of HDFS — a **schema kept in the Hive Metastore**
plus a **directory of files in HDFS**. We take one 1,000,000-row `sales` dataset and store it three
ways — **CSV**, **Parquet**, and **ORC** — each **partitioned by date (`dt`)**, all visible as
ordinary files and directories under `hdfs dfs -ls`. ([Lab 8](../lab8-yarn-hive-jobs/) runs the
identical build at **10,000,000 rows** on a YARN cluster.)

## The ideas

### The Hive Metastore
The **metastore** is a catalog. It remembers, in a relational database (here **Postgres**), what
tables exist, their columns and types, their storage format, and — crucially — the **HDFS
directory** where each table's data lives. It stores *no* table data itself, only metadata. Clients
talk SQL to **HiveServer2**, which consults the metastore and reads/writes files in HDFS.

```
beeline ──SQL──▶ HiveServer2 ──▶ Metastore (Postgres)   ← schema, format, location
                          └────▶ HDFS  /user/hive/warehouse/sales_parquet/*   ← the data
```

### Storage formats: CSV vs Parquet vs ORC
The same rows can be stored very differently:
- **CSV** (`STORED AS TEXTFILE`) — plain, **row-oriented** text. Human-readable, but big and slow to scan.
- **Parquet** and **ORC** (`STORED AS PARQUET` / `STORED AS ORC`) — **columnar** and compressed:
  values of a column sit together, so a query reads only the columns it needs and far fewer bytes.

You can tell the binary formats apart by their **magic numbers**: a Parquet file begins/ends with
`PAR1`; an ORC file begins with `ORC`. The lab writes all three from one CSV source and compares
their on-disk sizes with `hdfs dfs -du -h -s` — the columnar files are dramatically smaller.

### Partitioning (all three tables)
A **partitioned** table splits its data into a subdirectory per partition-key value. **Every** table
here is partitioned by `dt`, giving HDFS directories like `.../sales_parquet/dt=2026-01-01/`. A query
with `WHERE dt='2026-01-03'` then reads only that one directory — **partition pruning** — instead of
the whole table. The CSV data is laid out as `dt=…` directories on HDFS and registered with
`MSCK REPAIR TABLE`; the Parquet and ORC copies use *dynamic-partition* inserts that route each row
to its `dt` directory.

### Where the compute runs (and why there's no YARN here)
Loading the columnar/partitioned tables (`INSERT … SELECT`) compiles to MapReduce jobs. This lab has
**no cluster scheduler**, so it runs MapReduce **in-process (local mode)** inside HiveServer2. That's
why lab 7 uses 1M rows — enough to see real Parquet/ORC files and partition pruning while staying
quick on a single JVM:

```sql
SET mapreduce.framework.name=local;
```

**Lab 8** builds the *exact same* partitioned CSV/Parquet/ORC tables (at 10M rows) but runs every
load as a real distributed **YARN** job you can watch — the only difference is *where the compute
happens*.

## Run it

```bash
make up        # HDFS + Postgres metastore + HiveServer2 + Hue, waits until all are healthy
make demo      # build partitioned CSV/Parquet/ORC tables; find the files in HDFS
make verify    # automated PASS/FAIL checks
make beeline   # optional: open an interactive SQL shell
make metastore # show what the metastore keeps in Postgres (schemas, formats, partitions)
make ui        # print the web UI URLs
make clean
```

### Peek at the metastore's database

`make metastore` (run it after `make demo`) queries the metastore's own PostgreSQL directly and
prints the rows it keeps — the `DBS`/`TBLS`/`SDS`/`COLUMNS_V2`/`PARTITION_KEYS`/`PARTITIONS` tables.
You'll see each table's storage format (Parquet/ORC/Text), its `hdfs://…` location, its columns, the
`dt` partition key, and one row per `dt=…` partition. It's the concrete proof that the metastore
stores only *metadata pointing at HDFS* — never the table data itself.

### Write queries in the browser (Hue)

`make up` also starts **Hue**, a web SQL editor, at **http://localhost:8888**. On first visit
create any username/password (the first account becomes the admin). Then open the SQL editor, pick
the **Hive** dialect, and run queries against the same tables — e.g.:

```sql
SELECT country, sum(amount) FROM sales_parquet GROUP BY country;
```

Hue's file browser also lets you see the files under `/user/hive/warehouse`. (These queries run in
local mode, same as the demo — `make beeline` remains the reliable CLI alternative.)

## What to look for

- The CSV source is plain text in HDFS, laid out per day:
  `hdfs dfs -cat /data/sales/dt=2026-01-01/data.csv | head`.
- Columnar files carry magic numbers: `hdfs dfs -cat <parquet file> | head -c 4` → `PAR1`;
  `hdfs dfs -cat <orc file> | head -c 3` → `ORC`.
- Size comparison: `hdfs dfs -du -h -s /data/sales /user/hive/warehouse/sales_parquet /user/hive/warehouse/sales_orc`
  — Parquet/ORC are much smaller than the CSV.
- Partition layout: `hdfs dfs -ls /user/hive/warehouse/sales_parquet` shows one `dt=YYYY-MM-DD/`
  directory per day; `SHOW PARTITIONS sales_parquet` (in `make beeline`) lists them.

## What `make verify` checks

1. The **metastore is reachable** (`SHOW DATABASES` returns `default`).
2. A **1,000,000-row CSV**, laid out as `dt=…` directories, is registered by the partitioned external
   `sales_csv` table via `MSCK REPAIR` (5 partitions, `count = 1000000`).
3. `sales_parquet` (partitioned) holds the same 1,000,000 rows; its files are **really Parquet** (`PAR1`).
4. `sales_orc` (partitioned) holds the same 1,000,000 rows; its files are **really ORC** (`ORC`).
5. **Same data, three encodings** — csv = parquet = orc = 1,000,000.
6. **Partition pruning** — all three tables have 5 `dt=…` directories in HDFS, and a pruned
   `WHERE dt='2026-01-03'` returns 200,000.
