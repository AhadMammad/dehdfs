# Lab 2 — Blocks & Replication

**Goal:** see the two ideas at the heart of HDFS storage — files are chopped into fixed-size **blocks**,
and every block is **replicated** onto multiple DataNodes for durability.

## The idea

HDFS does not store a file as one contiguous object. It splits the file into fixed-size **blocks**
(128 MiB in production) and stores each block independently. Each block is then copied to several
DataNodes — the **replication factor**, 3 by default. If any one machine dies, every block still exists
elsewhere.

```
big.bin (5 MiB)
 ├─ block 0 ─┐
 ├─ block 1 ─┤  each block replicated ×3
 ├─ block 2 ─┼──▶ DataNode1  DataNode2  DataNode3
 ├─ block 3 ─┤
 └─ block 4 ─┘
```

This lab shrinks the block size to **1 MiB** so that a tiny 5 MiB file visibly becomes **5 blocks** —
you would need a 640 MiB file to see the same with the production default. It runs **3 DataNodes** so a
replication factor of 3 can actually be satisfied.

## Run it

```bash
make up       # 1 NameNode + 3 DataNodes
make demo     # write a 5 MiB file, then fsck it to see blocks + replica locations
make verify   # automated PASS/FAIL checks
make clean
```

## What to look for

`hdfs fsck /demo/big.bin -files -blocks -locations` prints one line per block, and each block lists the
**three DataNodes** holding a replica. The summary shows `Total blocks (validated): 5` and
`Average block replication: 3.0`. Open the NameNode UI (http://localhost:9870) → *Datanodes* to see all
three nodes and their block counts.

## What `make verify` checks

1. All 3 DataNodes are live.
2. `dfs.blocksize` is really 1 MiB.
3. The 5 MiB file becomes **exactly 5 blocks**.
4. Average replication is **3.0** with **0** under-replicated blocks.
5. A block's three replicas sit on **3 distinct DataNodes**.
