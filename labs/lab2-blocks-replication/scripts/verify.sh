#!/usr/bin/env bash
# Lab 2 verification — proves block-splitting and 3x replication.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
h() { $COMPOSE exec -T "$NN" "$@"; }

pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }
# Retry a command up to 3 times — the amd64 JVM occasionally aborts under emulation.
retry() { local n=0; until "$@"; do n=$((n+1)); [ "$n" -ge 3 ] && return 1; sleep 3; done; }
# Pull the Nth number out of the fsck line containing $1 (labels are tab-separated).
fsck_num() { echo "$1" | grep -a "$2" | grep -oE '[0-9]+(\.[0-9]+)?' | sed -n "${3:-1}p"; }

echo "==> Lab 2 checks"

# 0) Wait until all 3 DataNodes are live, otherwise replication can't reach 3.
echo "==> Waiting for 3 live DataNodes..."
for i in $(seq 1 40); do
	LIVE=$(h hdfs dfsadmin -report 2>/dev/null | sed -n 's/^Live datanodes (\([0-9]*\)).*/\1/p')
	[ "${LIVE:-0}" -ge 3 ] && break
	sleep 3
done
[ "${LIVE:-0}" -ge 3 ] || fail "expected 3 live DataNodes, found ${LIVE:-0}"
pass "3 live DataNodes registered"

# 1) Create a 5 MiB file. With a 1 MiB block size that must be exactly 5 blocks.
h hdfs dfs -mkdir -p /verify
h bash -c 'dd if=/dev/zero of=/tmp/big.bin bs=1M count=5 status=none && hdfs dfs -put -f /tmp/big.bin /verify/big.bin'
pass "wrote a 5 MiB file"

# 2) Confirm the configured block size really is 1 MiB.
BS=$(h hdfs getconf -confKey dfs.blocksize | tr -d '\r')
[ "$BS" = "1048576" ] || fail "expected dfs.blocksize=1048576, got '$BS'"
pass "block size is 1 MiB (1048576 bytes)"

# 3) fsck: exactly 5 blocks. (Retry once: the JVM can abort transiently under emulation.)
FSCK=$(h hdfs fsck /verify/big.bin 2>/dev/null) || FSCK=$(h hdfs fsck /verify/big.bin 2>/dev/null)
BLOCKS=$(fsck_num "$FSCK" 'Total blocks (validated)' 1)
[ "$BLOCKS" = "5" ] || fail "expected 5 blocks for a 5 MiB file, got '$BLOCKS'"
pass "file split into exactly 5 blocks"

# 4) fsck: average replication is 3.0 and nothing under-replicated.
AVG=$(fsck_num "$FSCK" 'Average block replication' 1)
[ "$AVG" = "3.0" ] || fail "expected average replication 3.0, got '$AVG'"
UNDER=$(fsck_num "$FSCK" 'Under-replicated blocks' 1)
[ "${UNDER:-0}" = "0" ] || fail "expected 0 under-replicated blocks, got '$UNDER'"
pass "every block is replicated 3x (avg replication 3.0, 0 under-replicated)"

# 5) Replicas are spread across 3 DISTINCT DataNodes.
# (Capture first, then filter — piping fsck straight into `head` trips pipefail via SIGPIPE.)
LOCOUT=$(h hdfs fsck /verify/big.bin -files -blocks -locations 2>/dev/null || true)
LOCS=$(printf '%s' "$LOCOUT" | grep -oE 'DatanodeInfoWithStorage\[[0-9.]+' | sort -u | wc -l | tr -d ' ')
[ "$LOCS" = "3" ] || fail "expected replicas across 3 distinct DataNodes, found $LOCS"
pass "block replicas are spread across 3 distinct DataNodes"

printf '\n\033[1;32mLab 2 PASS\033[0m — files split into blocks, each replicated 3x across nodes.\n'
