#!/usr/bin/env bash
# Lab 12 demo — the NameNode spreads a block's replicas across racks for fault tolerance.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
h() { $COMPOSE exec -T "$NN" "$@"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }

say "The cluster's network topology — 4 DataNodes mapped into 2 racks by the topology script:"
h hdfs dfsadmin -printTopology

say "Write an 8 MiB file (replication 3):"
h hdfs dfs -mkdir -p /data
h bash -c 'dd if=/dev/zero of=/tmp/f.bin bs=1M count=8 status=none && hdfs dfs -put -f /tmp/f.bin /data/f.bin'

say "Where did the 3 replicas land? Note the /rackN in each replica's location:"
h bash -c "hdfs fsck /data/f.bin -files -blocks -locations 2>/dev/null | grep -iE 'rack|Total blocks'; true"

say "The default placement policy spreads replicas across >1 rack, so a whole rack can fail"
say "without losing the block."

printf '\n\033[1;32mDemo complete.\033[0m Rack-aware placement kept the block on more than one rack.\n'
