# Lab 5 — WebHDFS REST, Quotas & Trash

**Goal:** reach HDFS without a Java client (over plain HTTP), and use two everyday operational features:
**quotas** (to stop a directory growing without bound) and the **trash** (to make `rm` recoverable).

## The ideas

### WebHDFS
Not every client wants to speak HDFS's native RPC protocol. **WebHDFS** exposes the whole filesystem as
an HTTP REST API, so you can `curl` it, call it from Python, or hit it from another language entirely.
A write is a two-step dance: you `PUT ...?op=CREATE` to the **NameNode**, which replies with a **307
redirect** to a **DataNode**, and the bytes are streamed there.

```
curl PUT .../op=CREATE ─▶ NameNode ─(307 redirect)─▶ DataNode ◀─ streams the file bytes
```

### Quotas
The NameNode can cap a directory by:
- **name quota** — the maximum number of files+directories (inodes) under a path, and
- **space quota** — the maximum number of bytes (counting replication) stored under a path.

Exceeding either makes the write fail — a guardrail against one team filling the whole cluster.

### Trash
With `fs.trash.interval > 0`, `hdfs dfs -rm` doesn't immediately destroy data — it **moves** the file to
a per-user `.Trash` directory, from which it can be restored until it's purged. `-skipTrash` forces
immediate, unrecoverable deletion.

## Run it

```bash
make up
make demo     # curl the WebHDFS API, hit a name quota and a space quota, delete into .Trash
make verify   # automated PASS/FAIL checks
make clean
```

## What to look for

- From your host you can browse WebHDFS directly:
  `curl 'http://localhost:9870/webhdfs/v1/?op=LISTSTATUS'` returns JSON.
- `hdfs dfs -count -q -h /path` shows the quota columns for a directory.
- After `hdfs dfs -rm somefile`, the shell prints *"Moved: ... to trash at: .../.Trash/Current/..."*.

## What `make verify` checks

1. WebHDFS `CREATE` (HTTP 201) + `OPEN` round-trips a file with identical content.
2. WebHDFS `LISTSTATUS` returns the file as JSON.
3. A **name quota** rejects the inode that would exceed it.
4. A **space quota** rejects an over-size write.
5. `rm` lands the file in **`.Trash`** (recoverable).
6. `rm -skipTrash` deletes immediately with **no** trash copy.
