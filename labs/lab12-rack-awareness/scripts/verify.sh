#!/usr/bin/env bash
# Lab 12 verification — the cluster spans 2 racks and a block's replicas are placed across them.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
h() { $COMPOSE exec -T "$NN" "$@"; }
pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

live() { h hdfs dfsadmin -report 2>/dev/null | grep -a 'Live datanodes' | grep -oE '[0-9]+' | head -1; }

echo "==> Lab 12 checks"

# 0) Wait for all 4 DataNodes.
for i in $(seq 1 40); do [ "$(live)" = "4" ] && break; sleep 3; done
[ "$(live)" = "4" ] || fail "expected 4 live DataNodes, found $(live)"
pass "4 live DataNodes registered"

# 1) The topology maps DataNodes into >=2 racks.
TOPO=$(h hdfs dfsadmin -printTopology 2>/dev/null)
RACKS=$(grep -oE '/rack[0-9]+' <<<"$TOPO" | sort -u | wc -l | tr -d ' ')
[ "${RACKS:-0}" -ge 2 ] || fail "topology shows $RACKS rack(s); expected >=2 (is topology.sh executable?)"
pass "cluster topology spans $RACKS racks"

# 2) A replicated block is placed across >=2 racks.
h hdfs dfs -mkdir -p /data
h bash -c 'dd if=/dev/zero of=/tmp/f.bin bs=1M count=8 status=none && hdfs dfs -put -f /tmp/f.bin /data/f.bin'
LOC=$(h hdfs fsck /data/f.bin -files -blocks -locations 2>/dev/null)
BR=$(grep -oE '/rack[0-9]+' <<<"$LOC" | sort -u | wc -l | tr -d ' ')
[ "${BR:-0}" -ge 2 ] || fail "block replicas span only $BR rack(s); expected >=2"
pass "the block's replicas span $BR racks (rack-aware placement)"

printf '\n\033[1;32mLab 12 PASS\033[0m — DataNodes are rack-mapped and replicas are spread across racks.\n'
