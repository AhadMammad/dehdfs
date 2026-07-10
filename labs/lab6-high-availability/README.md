# Lab 6 — High Availability (Automatic NameNode Failover)

**Goal:** remove the NameNode as a single point of failure. Run **two** NameNodes — one **active**, one
**standby** — and watch the standby take over **automatically** when the active dies, with no data loss.

> This is the most complex lab. It starts ~9 containers and the HA bootstrap (format → journal →
> bootstrap standby → ZK format) takes a few minutes on first `make up`. Be patient.

## The idea

In the basic labs there is exactly one NameNode. If it dies, the whole filesystem is unavailable — a
**single point of failure**. HA fixes this with several cooperating pieces:

- **Two NameNodes** — `nn1` and `nn2`. At any moment one is **active** (serves clients) and one is
  **standby** (kept in sync, ready to take over).
- **JournalNode quorum** (`jn1/jn2/jn3`) — a shared, replicated **edit log**. The active writes every
  change here; the standby reads it, staying byte-for-byte current.
- **ZooKeeper** + **ZKFC** (ZooKeeper Failover Controller) — each NameNode has a ZKFC that holds a lock
  in ZooKeeper. If the active's ZKFC loses its ZooKeeper session (because the node died), the standby's
  ZKFC wins the lock and **promotes** its NameNode to active — automatically.

```
             ┌── ZooKeeper ──┐         clients talk to  hdfs://mycluster
             │  (election)   │                 │
        ZKFC │               │ ZKFC            ▼
        ┌────┴────┐     ┌────┴────┐    (whichever NN is active)
        │  nn1    │     │  nn2    │
        │ ACTIVE  │     │ STANDBY │
        └────┬────┘     └────┬────┘
             │  shared edit log │
          ┌──┴──────┬──────────┴──┐
          │ jn1     │ jn2      jn3 │   (JournalNode quorum)
          └─────────┴─────────────┘
             DataNodes: dn1 dn2 dn3   (report to BOTH NameNodes)
```

## How this lab is wired

Unlike the other labs (which configure Hadoop purely through environment variables), HA needs explicit
XML. This lab mounts hand-written [`config/core-site.xml`](config/core-site.xml) and
[`config/hdfs-site.xml`](config/hdfs-site.xml) into every container, and a single
[`scripts/ha-entrypoint.sh`](scripts/ha-entrypoint.sh) that — based on `$HA_ROLE` — formats the
namespace, bootstraps the standby, formats the ZooKeeper failover znode, and starts each daemon
alongside its ZKFC.

## Run it

```bash
make up        # ~9 containers; waits until one NameNode is ACTIVE (can take a few minutes)
make state     # show which NameNode is active vs standby
make demo      # write data, kill the active NN, watch the standby get promoted, read data back
make verify    # automated PASS/FAIL checks (kills the active NN and asserts failover + durability)
make ui        # nn1 UI http://localhost:9870 , nn2 UI http://localhost:9871
make clean
```

## What to look for

- `hdfs haadmin -getAllServiceState` shows `nn1 ... active` / `nn2 ... standby` (or vice-versa).
- After `docker compose stop <active>`, within seconds `hdfs haadmin -getServiceState` on the survivor
  flips to **active** — no human ran a failover command.
- A file written before the failover is still readable afterwards: the standby had the full edit log.

## What `make verify` checks

1. The cluster starts with **exactly one active + one standby** NameNode.
2. Data is written through the logical nameservice `hdfs://mycluster`.
3. Killing the active NameNode triggers **automatic** promotion of the standby to active.
4. The pre-failover data is **still readable** from the new active NameNode (no data loss).
5. The cluster is still **writable** after failover.
6. The restarted old NameNode **rejoins as standby** (not a second active — no split brain).
