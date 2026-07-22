# Lab 10 — HDFS Snapshots

**Goal:** protect a directory with **snapshots** — cheap, read-only, point-in-time images you can
restore from after an accidental delete or overwrite.

## The idea

A **snapshot** captures the state of a directory subtree at an instant. It's nearly free: HDFS
doesn't copy any data, it just records the metadata, and only diverges as files change afterward.
The snapshot is **read-only** and lives under a hidden `.snapshot/<name>` path, so even files you
later delete from the live directory remain recoverable from the snapshot.

```
/data/report.txt              ← delete this from the live tree...
/data/.snapshot/snap1/report.txt   ← ...and it's still here, unchanged
```

## Run it

```bash
make up
make demo      # snapshot /data, delete + overwrite files, then restore from the snapshot
make verify    # automated PASS/FAIL checks
make clean
```

## What to look for

- `hdfs dfsadmin -allowSnapshot /data` then `hdfs dfs -createSnapshot /data snap1`.
- After deleting a file, it's gone from `hdfs dfs -ls /data` but still in
  `hdfs dfs -ls /data/.snapshot/snap1`.
- `hdfs snapshotDiff /data snap1 .` lists what changed (`+` added, `-` deleted, `M` modified).

## What `make verify` checks

1. A **snapshot** `snap1` of `/data` is created.
2. A file **deleted** from the live directory is gone from `/data`.
3. `snapshotDiff` **reports the change** since `snap1`.
4. The deleted file **still exists in the snapshot**, byte-for-byte.
5. It can be **restored** from the snapshot.
