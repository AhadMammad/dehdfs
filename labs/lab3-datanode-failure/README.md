# Lab 3 — DataNode Failure & Recovery

**Goal:** watch HDFS do the thing it was built for — survive a machine failure automatically, with no
data loss and no human intervention.

## The idea

DataNodes send a **heartbeat** to the NameNode every few seconds. If the NameNode stops hearing from a
node, it eventually marks it **dead**. Every block that lived on the dead node is now
**under-replicated** (fewer than the target 3 copies), so the NameNode schedules **re-replication**:
it tells surviving DataNodes to copy those blocks until the replication factor is met again.

```
  before:  [DN1][DN2][DN3][DN4]      block copies spread across 4 nodes
   kill DN4 ─────────────┐
  after:   [DN1][DN2][DN3] ✗DN4      NameNode copies the missing replicas
           back to 3 copies each     onto the 3 survivors — automatically
```

This lab runs **4 DataNodes** with replication **3**, so after one node dies there is still room to
restore three full copies. Dead-node detection is tuned down to **~60 seconds** (production defaults take
~10.5 minutes) so the recovery is watchable.

## Run it

```bash
make up       # 1 NameNode + 4 DataNodes
make demo     # write a file, kill a DataNode, watch live-count drop and blocks re-replicate
make verify   # automated PASS/FAIL checks (this one takes a couple of minutes)
make clean
```

> `verify`/`demo` take longer than other labs because they wait for the ~60s dead-node timeout plus
> re-replication.

## What to look for

- Open the NameNode UI (http://localhost:9870) → *Datanodes*: after `docker compose stop datanode4` the
  node moves from **In Service** to **Dead**.
- `hdfs fsck /` shows `Under-replicated blocks` spike above zero, then fall back to **0** as the
  survivors receive the missing copies.
- The file's `hdfs dfs -checksum` is identical before and after — the failure was invisible to the data.

## What `make verify` checks

1. All 4 DataNodes are live and the file starts fully replicated.
2. After stopping one node, the NameNode detects the death (live count drops to 3).
3. The cluster **self-heals**: under-replicated and missing blocks both return to **0**.
4. The file checksum is **unchanged** — zero data loss.
