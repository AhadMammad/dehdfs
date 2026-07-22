# Lab 9 — Erasure Coding

**Goal:** see HDFS store data with **erasure coding (EC)** — striped data + parity — as a
space-efficient alternative to the 3× replication from [lab 2](../lab2-blocks-replication/). Same
fault tolerance, far less disk.

## The idea

Three-way replication is simple but expensive: every byte is stored **3×**. **Erasure coding**
instead splits data into cells, computes **parity** cells, and stripes them across DataNodes. With
the **`RS-3-2`** policy, every 3 data cells get 2 parity cells — so you can lose **any 2** of the 5
and still rebuild the data, at only **~1.67× overhead** instead of 3×.

```
3x replication:  [D][D][D]                 -> 3.00x storage, survives 2 losses
RS-3-2 EC:       [d1][d2][d3][p1][p2]       -> 1.67x storage, survives 2 losses
```

EC needs at least `data+parity` DataNodes (RS-3-2 → 5), so this lab runs **6**. Reads transparently
**reconstruct** missing cells from parity, so a file stays available when a node dies.

## Run it

```bash
make up        # 1 NameNode + 6 DataNodes
make demo      # enable RS-3-2, compare EC vs replicated storage, survive a node loss
make verify    # automated PASS/FAIL checks
make clean
```

## What to look for

- `hdfs ec -listPolicies` / `hdfs ec -getPolicy -path /ec` — the policy set on the directory.
- `hdfs dfs -du -s -v /rep/big.bin /ec/big.bin` — the 2nd column (disk consumed) is ~3× the file
  for `/rep` but only ~1.67× for `/ec`.
- `hdfs fsck /ec/big.bin -files -blocks` — the file is one striped block group, not replicas.

## What `make verify` checks

1. All **6 DataNodes** are live (EC needs ≥5).
2. The **`RS-3-2` policy** is enabled and set on `/ec`.
3. The EC copy of a 16 MiB file **consumes less disk** than the 3×-replicated copy.
4. `fsck` reports the `/ec` file as **erasure-coded**.
5. After **stopping a DataNode**, the EC file still reads back **byte-for-byte** (reconstruction).
