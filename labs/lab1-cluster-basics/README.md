# Lab 1 — Cluster Basics & the FS Shell

**Goal:** understand the two roles that make up every HDFS cluster and drive the filesystem with the
`hdfs dfs` shell.

## The idea

An HDFS cluster is split into two kinds of process:

- **NameNode** — the "brain". It holds the **namespace** (the directory tree, file names, permissions)
  and knows which **blocks** make up each file and which DataNodes hold them. It stores *metadata*, not
  file data.
- **DataNode** — the "muscle". It stores the actual block data on local disk and serves it to clients.

This lab runs exactly one of each — the smallest cluster that can store a file.

```
client ──(hdfs dfs)──▶ NameNode  (namespace + block map)
                          │
                          ▼
                       DataNode   (block data on disk)
```

## Run it

```bash
make up       # start NameNode + DataNode, wait until ready
make demo     # narrated tour: mkdir, put, ls, cat, get, du, df, tail, rm
make verify   # automated PASS/FAIL checks
make ui       # NameNode UI http://localhost:9870 , DataNode UI http://localhost:9864
make clean    # stop and delete volumes
```

## What to look for

- Open the **NameNode UI** at http://localhost:9870 → *Utilities → Browse the file system* and watch the
  files you create appear.
- `hdfs dfsadmin -report` lists the live DataNode(s), capacity, and usage.
- The `put`→`cat`→`get` round-trip shows a file surviving a trip through the block storage unchanged.

## What `make verify` checks

1. At least one live DataNode is reporting in.
2. `mkdir` creates a namespace path.
3. `put` + `cat` round-trips a file with identical content.
4. `ls` lists the file.
5. `rm` deletes it.
