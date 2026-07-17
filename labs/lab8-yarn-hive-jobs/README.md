# Lab 8 — The Same Multi-Format Build, on YARN

**Goal:** take the *exact* partitioned CSV/Parquet/ORC build from
[Lab 7](../lab7-hive-metastore-parquet/) — now at **10,000,000 rows** — and run every load as a real
distributed job on **YARN**, so you can see *where the compute happens*. The SQL is identical and the
files on HDFS are identical; the only difference is that each `INSERT … SELECT` is now scheduled onto
a cluster instead of running in-process. (Lab 7 does the same build at 1M rows in local mode; the
cluster here is what makes 10M practical.)

## The ideas

### YARN — Hadoop's resource manager
In Lab 7 the `INSERT` ran inside HiveServer2 (local mode). Real clusters don't work that way: a
central scheduler hands jobs out to worker machines. That's **YARN**:

- **ResourceManager** — one per cluster. Tracks all CPU/memory and decides where each job runs.
  Web UI on **:8088** — this is where you watch jobs.
- **NodeManager** — one per worker. Launches and supervises the **containers** that run the actual
  map/reduce tasks. This lab runs **two** of them.
- **ApplicationMaster** — a per-job coordinator YARN starts in a container; it asks the
  ResourceManager for more containers and drives the job to completion.

```
beeline ─▶ HiveServer2 ─submits job─▶ ResourceManager :8088
                                         ├─▶ NodeManager 1 ─▶ container (map/reduce task)
                                         └─▶ NodeManager 2 ─▶ container (map/reduce task)
                                                 └─writes─▶ HDFS /user/hive/warehouse/sales_*/…
```

### The one change from Lab 7
The tables, the SQL, and the CSV/Parquet/ORC + partitioned files are the same. Only the execution
engine differs:

```sql
-- Lab 7:  SET mapreduce.framework.name=local;   (in-process, no scheduler)
-- Lab 8:  SET mapreduce.framework.name=yarn;     (scheduled onto the cluster)
```

The output is byte-for-byte the same — proving *storage* (Lab 7) and *compute* (Lab 8) are separate
concerns layered over HDFS.

## Run it

```bash
make up        # HDFS + YARN (RM + 2 NodeManagers + history) + metastore + HiveServer2 + Hue
make demo      # build CSV/Parquet/ORC + partitioned tables as YARN jobs; watch at http://localhost:8088
make verify    # automated PASS/FAIL checks
make apps      # list YARN applications (see the finished INSERT job)
make metastore # show what the metastore keeps in Postgres (schemas, formats, partitions)
make ui        # print all the web UIs
make clean
```

### Peek at the metastore's database

`make metastore` (run it after `make demo`) queries the metastore's own PostgreSQL directly and
prints the `DBS`/`TBLS`/`SDS`/`COLUMNS_V2`/`PARTITION_KEYS`/`PARTITIONS` rows — each table's storage
format, its `hdfs://…` location, columns, the `dt` partition key, and one row per `dt=…` partition.
Concrete proof the metastore stores only *metadata pointing at HDFS*, never the data itself.

### Write queries in the browser (Hue)

`make up` also starts **Hue**, a web SQL editor, at **http://localhost:8888** (create any
username/password on first visit). Run a query there and — because this lab is wired to YARN — it
becomes a YARN application: watch it appear at the ResourceManager UI (**http://localhost:8088**)
while it runs. `make beeline` remains the reliable CLI alternative.

## What to look for

- Open **http://localhost:8088** during `make demo` and watch each load go
  SUBMITTED → RUNNING → FINISHED (FinalStatus SUCCEEDED) — one application per `INSERT`.
- `make apps` lists the finished applications; these are the jobs that wrote your Parquet/ORC/
  partitioned files.
- Every table is partitioned in HDFS: `hdfs dfs -ls /user/hive/warehouse/sales_parquet` shows
  `dt=YYYY-MM-DD/` directories; files start with `PAR1` (Parquet) / `ORC` (ORC).

## What `make verify` checks

1. **YARN is up** — both NodeManagers are registered and `RUNNING`.
2. A **10,000,000-row CSV**, laid out as `dt=…` directories, is registered by the partitioned external
   `sales_csv` table via `MSCK REPAIR` (5 partitions, `count = 10000000`).
3. `sales_parquet` (partitioned) holds the same 10,000,000 rows, stored as **Parquet** (`PAR1`).
4. `sales_orc` (partitioned) holds the same 10,000,000 rows, stored as **ORC** (`ORC`).
5. **Same data, three encodings** — csv = parquet = orc = 10,000,000.
6. **Partition pruning** — all three tables have 5 `dt=…` directories; a pruned `WHERE dt='2026-01-03'`
   returns 2,000,000.
7. **The loads really ran on YARN** — new applications finished with FinalStatus `SUCCEEDED` (the
   assertion that distinguishes Lab 8 from Lab 7's local mode).
