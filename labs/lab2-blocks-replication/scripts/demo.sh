#!/usr/bin/env bash
# Lab 2 demo — watch a single file split into blocks, each replicated across DataNodes.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
h() { $COMPOSE exec -T "$NN" "$@"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }

say "Three DataNodes are registered:"
h hdfs dfsadmin -report | grep -E 'Live datanodes|Name:' || true

say "Block size is 1 MiB in this lab (see dfs.blocksize). Create a 5 MiB file:"
h bash -c 'dd if=/dev/zero of=/tmp/big.bin bs=1M count=5 status=none'
h hdfs dfs -mkdir -p /demo
h hdfs dfs -put -f /tmp/big.bin /demo/big.bin

say "5 MiB / 1 MiB block => the file is stored as MULTIPLE blocks. Ask fsck to prove it:"
h hdfs fsck /demo/big.bin -files -blocks -locations

say "The summary lines: note 'Total blocks' and 'Average block replication':"
h hdfs fsck /demo/big.bin | grep -E 'Total blocks|Average block replication|Under-replicated|replicated blocks'

printf '\n\033[1;32mDemo complete.\033[0m Each block above is listed with 3 DataNode locations.\n'
