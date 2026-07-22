# Lab 12 — Rack Awareness

**Goal:** see how HDFS spreads a block's replicas **across racks** so a whole rack can fail without
losing data — and how a small **topology script** tells the NameNode which node is on which rack.

## The idea

Real clusters group machines into **racks** (a rack shares a switch and a power supply, so a rack
can fail as a unit). HDFS's default placement policy for 3 replicas is: one on the writer's rack, and
the other two on a **different** rack. That way losing one rack still leaves a copy.

The NameNode learns the layout from a **topology script** (`net.topology.script.file.name`): it
calls the script with a DataNode's IP and the script prints that node's rack path.

```
/rack1 ── dn1 (172.28.1.1), dn2 (172.28.1.2)
/rack2 ── dn3 (172.28.2.1), dn4 (172.28.2.2)
```

This lab gives the DataNodes **static IPs** so [`config/topology.sh`](config/topology.sh) can map
`172.28.1.*` → `/rack1` and `172.28.2.*` → `/rack2` deterministically.

## Run it

```bash
make up
make demo      # print the topology, write a file, see its replicas span both racks
make verify    # automated PASS/FAIL checks
make clean
```

## What to look for

- `hdfs dfsadmin -printTopology` groups the DataNodes under `Rack: /rack1` and `Rack: /rack2`.
- `hdfs fsck /data/f.bin -files -blocks -locations` shows each replica's location prefixed with its
  rack, e.g. `/rack1/172.28.1.1:9866` — and they don't all sit on one rack.

## What `make verify` checks

1. All **4 DataNodes** are live.
2. The topology maps them into **≥2 racks** (`printTopology`).
3. A replicated block's copies are **placed across ≥2 racks** (`fsck -locations`).
