# dehdfs — Learn HDFS by Running It

A self-contained, Docker Compose–based learning resource for the **Hadoop Distributed File System
(HDFS)**. It pairs a fact-based, fully-offline explainer with **eighteen hands-on labs**, each with its own
Compose stack, `Makefile`, and an automated `make verify` that proves the lab does what it claims.

> HDFS is the storage layer that made "big data" practical: it stores enormous files reliably across a
> cluster of ordinary, failure-prone machines. These labs let you *see* how that works — blocks,
> replication, self-healing, metadata, the REST API, and high availability — instead of just reading
> about it.

## Contents

- **`docs/index.html`** — an illustrated (inline-SVG diagrams, no internet needed) explainer of what
  HDFS is, why it exists, and how its most-used features work. Open it in any browser:

  ```bash
  make docs        # prints the path; open it in your browser
  ```

- **`labs/`** — eighteen independent labs. Each is a separate Compose project you can start, explore,
  verify, and tear down on its own.

## Prerequisites

- **Docker** (Engine 20.10+) and **Docker Compose v2** (`docker compose ...`)
- **GNU Make**
- A few GB of free RAM/disk. Lab 6 (HA) is the heaviest (multiple NameNodes + JournalNodes + ZooKeeper).

Verified working with Docker 24.x and Compose v2.20. The `bde2020/hadoop` images are `amd64`; on Apple
Silicon they run under emulation (slower but fine).

## The eighteen labs

| # | Lab | What you learn | Key command to see it |
|---|-----|----------------|-----------------------|
| 1 | [Cluster basics & FS shell](labs/lab1-cluster-basics/) | NameNode vs DataNode, the namespace, the `hdfs dfs` shell | `hdfs dfs -put/-ls/-cat` |
| 2 | [Blocks & replication](labs/lab2-blocks-replication/) | Files split into blocks; each block replicated ×3 across DataNodes | `hdfs fsck -files -blocks -locations` |
| 3 | [DataNode failure & recovery](labs/lab3-datanode-failure/) | Heartbeats, dead-node detection, automatic re-replication | stop a DataNode, watch it self-heal |
| 4 | [NameNode metadata](labs/lab4-namenode-metadata/) | `fsimage` + edit log, safemode, checkpointing | `hdfs dfsadmin -saveNamespace`, `hdfs oiv` |
| 5 | [WebHDFS, quotas & trash](labs/lab5-webhdfs-quotas-trash/) | The HTTP REST API, space/name quotas, the `.Trash` safety net | `curl .../webhdfs/v1/...` |
| 6 | [High Availability](labs/lab6-high-availability/) | Active/standby NameNodes, JournalNode quorum, ZooKeeper + ZKFC failover | kill the active NameNode, watch failover |
| 7 | [Hive Metastore & Parquet](labs/lab7-hive-metastore-parquet/) | A table = a metastore schema + Parquet files in HDFS; columnar storage | `CREATE TABLE ... STORED AS PARQUET`, then `hdfs dfs -ls /user/hive/warehouse` |
| 8 | [The same write, on YARN](labs/lab8-yarn-hive-jobs/) | ResourceManager/NodeManagers run the Parquet write as a distributed job | watch the INSERT job at `:8088` |
| 9 | [Erasure coding](labs/lab9-erasure-coding/) | Striped data + parity vs 3× replication — same safety, ~1.67× storage | `hdfs ec -setPolicy`, compare `hdfs dfs -du` |
| 10 | [Snapshots](labs/lab10-snapshots/) | Cheap point-in-time directory images; recover deleted files | `hdfs dfs -createSnapshot`, restore from `.snapshot/` |
| 11 | [Permissions & ACLs](labs/lab11-permissions-acls/) | POSIX owner/group/other bits plus extended per-user ACLs | `hdfs dfs -setfacl -m user:bob:r-x` |
| 12 | [Rack awareness](labs/lab12-rack-awareness/) | A topology script; replicas spread across racks | `hdfs dfsadmin -printTopology`, `fsck -locations` |
| 13 | [Bucketing](labs/lab13-bucketing/) | Hashing a column into a fixed set of files; sampling & joins | `CLUSTERED BY (id) INTO 8 BUCKETS`, `TABLESAMPLE` |
| 14 | [ACID transactions](labs/lab14-acid-transactions/) | UPDATE/DELETE via delta files + compaction on transactional ORC | `UPDATE`/`DELETE`, `ALTER TABLE … COMPACT` |
| 15 | [Formats & schema evolution](labs/lab15-formats-schema-evolution/) | Avro vs Parquet/ORC, compression codecs, adding columns | `STORED AS AVRO`, `ALTER TABLE … ADD COLUMNS` |
| 16 | [External vs managed](labs/lab16-external-vs-managed/) | What `DROP TABLE` does to the data in HDFS | `DROP` a managed vs an external table |
| 17 | [Trino over the metastore](labs/lab17-trino-metastore/) | An MPP engine querying the same tables from HDFS, no MapReduce | `trino --catalog hive`, watch `:8080` |
| 18 | [Spark SQL](labs/lab18-spark-sql/) | Spark reading/writing the same Hive warehouse over HDFS | `spark-sql` reads/writes the shared metastore |

## Standard per-lab workflow

Every lab exposes the **same** `make` targets, so once you learn one you know them all:

```bash
cd labs/lab1-cluster-basics

make up        # start the cluster (waits until the NameNode is ready)
make demo      # run a guided, narrated walkthrough of the lab's concept
make verify    # automated assertions -> prints PASS or FAIL
make ui        # print the web UI URLs (NameNode :9870, DataNode :9864)
make shell     # open a shell inside the NameNode container
make logs      # follow container logs
make clean     # stop everything and delete the volumes (frees ports/disk)
```

Recommended first run: `make up && make demo && make verify && make clean`.

## Verify everything at once

From the repo root:

```bash
make verify-all   # runs each lab: up -> verify -> clean, then prints an aggregate summary
make clean-all    # tear down every lab (safety net if something was left running)
make help         # list root targets
```

Because the labs reuse the standard HDFS ports, run them **one at a time** (or use `verify-all`, which
serialises them and cleans up between each).

## How verification works

Each lab ships `scripts/verify.sh`, which runs real HDFS commands *inside* the running cluster and
asserts concrete outcomes — e.g. "this 5 MB file became exactly 5 blocks", "after killing a DataNode the
cluster returned to zero under-replicated blocks", "the standby NameNode became Active within the
timeout and the data survived". A failed assertion prints a red `FAIL:` line and exits non-zero; success
prints a green `PASS`. Nothing is eyeballed.
