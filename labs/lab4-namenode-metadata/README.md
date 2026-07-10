# Lab 4 — NameNode Metadata: fsimage, Edit Log, Safemode & Checkpointing

**Goal:** understand how the NameNode keeps the namespace durable, why there are *two* metadata files
(not one), and what safemode and checkpointing are for.

## The idea

The NameNode holds the whole namespace **in RAM** for speed, but it must also survive a restart. It does
that with two files on disk:

- **`fsimage`** — a **checkpoint**: a complete snapshot of the namespace at one point in time.
- **`edits` (the edit log)** — an append-only **journal** of every change made *since* the last
  checkpoint.

Writing a fresh full snapshot on every change would be far too slow, so the NameNode instead just
**appends** each change to the edit log. On restart it loads the last `fsimage` and then **replays** the
edit log to catch up to the present.

```
   startup:   fsimage (snapshot)  +  edits (journal of changes)  ─▶ namespace in RAM
   checkpoint:  fsimage  ⊕  edits  ─────────────────────────────▶ new, bigger fsimage
                                                                   (edit log resets)
```

A **checkpoint** merges the edit log back into a new `fsimage` (so the edit log doesn't grow forever). In
production a Secondary/Standby NameNode does this on a schedule; here we trigger it by hand with
`hdfs dfsadmin -saveNamespace`.

**Safemode** is the read-only state the NameNode enters on startup: it loads the metadata and waits for
DataNodes to report their blocks before it will allow any writes. `saveNamespace` also requires safemode
(so the namespace can't change mid-checkpoint).

## Run it

```bash
make up
make demo     # locate fsimage/edits, grow the edit log, safemode, checkpoint, inspect with 'hdfs oiv'
make verify   # automated PASS/FAIL checks
make clean
```

## What to look for

- `ls /hadoop/dfs/name/current` inside the NameNode shows `fsimage_*`, `edits_*`, and `seen_txid`.
- After `hdfs dfsadmin -saveNamespace`, a **new** `fsimage_*` appears with a **higher transaction id**.
- `hdfs oiv` (Offline Image Viewer) turns the binary fsimage into readable XML; `hdfs oev` does the same
  for the edit log.
- A write attempted while in safemode fails with *"Name node is in safe mode."*

## What `make verify` checks

1. The metadata files exist in `/hadoop/dfs/name/current`.
2. Safemode toggles **ON** and **OFF** on demand.
3. Writes are **rejected** while in safemode.
4. `saveNamespace` produces a new fsimage with a **higher transaction id** (a real checkpoint happened).
5. After leaving safemode, writes work again.
