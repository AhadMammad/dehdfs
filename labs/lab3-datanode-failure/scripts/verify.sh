#!/usr/bin/env bash
# Lab 3 verification — proves automatic re-replication after a DataNode dies.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
VICTIM=datanode4
h() { $COMPOSE exec -T "$NN" "$@"; }

pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

# fsck/report separate labels from numbers with TABs, so match on the label then grab the number.
live()  { h hdfs dfsadmin -report 2>/dev/null | grep -a 'Live datanodes' | grep -oE '[0-9]+' | head -1; }
under() { h hdfs fsck / 2>/dev/null | grep -a 'Under-replicated blocks' | grep -oE '[0-9]+' | head -1; }
missing(){ h hdfs fsck / 2>/dev/null | grep -a 'Missing blocks' | grep -oE '[0-9]+' | head -1; }

echo "==> Lab 3 checks"

# 0) Wait for all 4 DataNodes.
for i in $(seq 1 40); do [ "$(live)" = "4" ] && break; sleep 3; done
[ "$(live)" = "4" ] || fail "expected 4 live DataNodes, found $(live)"
pass "4 live DataNodes registered"

# 1) Write a replicated file and confirm it starts fully replicated.
h hdfs dfs -mkdir -p /verify
h bash -c 'dd if=/dev/zero of=/tmp/data.bin bs=1M count=8 status=none && hdfs dfs -put -f /tmp/data.bin /verify/data.bin'
CKSUM_BEFORE=$(h hdfs dfs -checksum /verify/data.bin | awk '{print $2}')
[ "$(under)" = "0" ] || fail "file started under-replicated"
pass "wrote an 8 MiB file, 0 under-replicated blocks to start"

# 2) Kill one DataNode.
echo "==> Stopping $VICTIM to simulate a hardware failure..."
$COMPOSE stop "$VICTIM" >/dev/null
pass "stopped $VICTIM"

# 3) Wait for the NameNode to notice the death (Live datanodes drops to 3).
echo "==> Waiting for the NameNode to declare the node dead (~60s)..."
DEAD=0
for i in $(seq 1 40); do
	if [ "$(live)" = "3" ]; then DEAD=1; break; fi
	sleep 5
done
[ "$DEAD" = "1" ] || fail "NameNode never declared the node dead (still $(live) live)"
pass "NameNode detected the dead node (3 live DataNodes)"

# 4) Wait for self-healing: 0 under-replicated AND 0 missing blocks on the survivors.
echo "==> Waiting for automatic re-replication to restore full replication..."
HEALED=0
for i in $(seq 1 40); do
	U=$(under); M=$(missing)
	printf '   under-replicated=%s missing=%s\n' "${U:-?}" "${M:-?}"
	if [ "${U:-9}" = "0" ] && [ "${M:-9}" = "0" ]; then HEALED=1; break; fi
	sleep 5
done
[ "$HEALED" = "1" ] || fail "cluster did not heal in time (under=$(under) missing=$(missing))"
pass "cluster self-healed: 0 under-replicated, 0 missing blocks"

# 5) The data itself is unchanged (same checksum) despite losing a node.
CKSUM_AFTER=$(h hdfs dfs -checksum /verify/data.bin | awk '{print $2}')
[ "$CKSUM_BEFORE" = "$CKSUM_AFTER" ] || fail "checksum changed after failure (data corruption!)"
pass "file checksum unchanged — no data lost"

printf '\n\033[1;32mLab 3 PASS\033[0m — HDFS detected a dead node and re-replicated with no data loss.\n'
