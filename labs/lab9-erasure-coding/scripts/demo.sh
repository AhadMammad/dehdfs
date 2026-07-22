#!/usr/bin/env bash
# Lab 9 demo — erasure coding: striped data + parity instead of 3x replication.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
POLICY=RS-3-2-1024k

h() { $COMPOSE exec -T "$NN" "$@"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }

say "Erasure coding policies this Hadoop build ships with:"
h hdfs ec -listPolicies 2>/dev/null | grep -iE 'name|state' | head -n 20 || true

say "Enable $POLICY — 3 data + 2 parity cells, so it tolerates losing any 2 blocks:"
h hdfs ec -enablePolicy -policy "$POLICY" 2>/dev/null || true

say "Two directories: /rep (normal 3x replication) and /ec (erasure coded):"
h hdfs dfs -mkdir -p /rep /ec
h hdfs ec -setPolicy -path /ec -policy "$POLICY"
h hdfs ec -getPolicy -path /ec

say "Write the SAME 16 MiB file into each:"
h bash -c 'dd if=/dev/urandom of=/tmp/big.bin bs=1M count=16 status=none'
h hdfs dfs -put -f /tmp/big.bin /rep/big.bin
h hdfs dfs -put -f /tmp/big.bin /ec/big.bin

say "Disk space consumed (2nd column) — 3x replication vs ~1.67x for EC:"
h hdfs dfs -du -s -v /rep/big.bin /ec/big.bin

say "fsck shows /ec/big.bin is stored as a striped erasure-coded block group:"
h bash -c "hdfs fsck /ec/big.bin -files -blocks 2>/dev/null | grep -iE 'policy|erasure|Total blocks'; true"

say "Fault tolerance: stop a DataNode, then read the EC file back — it rebuilds from parity:"
$COMPOSE stop datanode6 >/dev/null
GOT=$(h bash -c "hdfs dfs -cat /ec/big.bin 2>/dev/null | wc -c" | tr -d '\r')
echo "read $GOT bytes back from /ec/big.bin after losing datanode6"

printf '\n\033[1;32mDemo complete.\033[0m Erasure coding = data + parity striped across nodes: less space than 3x, still fault tolerant.\n'
