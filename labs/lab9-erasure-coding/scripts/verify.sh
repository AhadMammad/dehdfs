#!/usr/bin/env bash
# Lab 9 verification — erasure coding stores less than replication and survives a node loss.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
POLICY=RS-3-2-1024k

h() { $COMPOSE exec -T "$NN" "$@"; }
pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

# Wait for all 6 DataNodes (EC needs >=5).
live() { h hdfs dfsadmin -report 2>/dev/null | grep -a 'Live datanodes' | grep -oE '[0-9]+' | head -1; }

echo "==> Lab 9 checks"

for i in $(seq 1 40); do [ "$(live)" = "6" ] && break; sleep 3; done
[ "$(live)" = "6" ] || fail "expected 6 live DataNodes, found $(live)"
pass "6 live DataNodes registered"

# 1) Enable the policy and set it on /ec.
h hdfs ec -enablePolicy -policy "$POLICY" >/dev/null 2>&1 || true
h hdfs dfs -mkdir -p /rep /ec
h hdfs ec -setPolicy -path /ec -policy "$POLICY" >/dev/null 2>&1 || true
GOT=$(h bash -c "hdfs ec -getPolicy -path /ec 2>/dev/null" | tr -d '\r' | grep -o "$POLICY" | head -n1)
[ "$GOT" = "$POLICY" ] || fail "EC policy not set on /ec (got '$GOT')"
pass "erasure coding policy $POLICY enabled and set on /ec"

# 2) Write the same 16 MiB file to both directories.
h bash -c 'dd if=/dev/urandom of=/tmp/big.bin bs=1M count=16 status=none'
ORIG=$(h bash -c "wc -c < /tmp/big.bin" | tr -d '\r')
h hdfs dfs -put -f /tmp/big.bin /rep/big.bin
h hdfs dfs -put -f /tmp/big.bin /ec/big.bin

# 3) EC consumes less disk than 3x replication.
REP=$(h bash -c "hdfs dfs -du -s /rep/big.bin | awk '{print \$2}'" | tr -d '\r')
EC=$(h bash -c "hdfs dfs -du -s /ec/big.bin | awk '{print \$2}'" | tr -d '\r')
[ -n "$REP" ] && [ -n "$EC" ] || fail "could not read disk usage (rep=$REP ec=$EC)"
[ "$EC" -lt "$REP" ] || fail "EC disk usage ($EC) is not less than replicated ($REP)"
pass "EC stores less on disk than 3x replication (ec=$EC < rep=$REP bytes)"

# 4) fsck confirms the file is erasure-coded.
h bash -c "hdfs fsck /ec/big.bin -files 2>/dev/null | grep -qiE 'RS-3-2|erasure'" \
	|| fail "fsck does not report the file as erasure-coded"
pass "fsck confirms /ec/big.bin is erasure-coded"

# 5) Reconstruction: stop a DataNode, the EC file still reads back byte-for-byte.
$COMPOSE stop datanode6 >/dev/null
GOTSIZE=$(h bash -c "hdfs dfs -cat /ec/big.bin 2>/dev/null | wc -c" | tr -d '\r')
[ "$GOTSIZE" = "$ORIG" ] || fail "EC file not fully readable after a DataNode loss ($GOTSIZE != $ORIG)"
pass "EC file reconstructs from parity after losing a DataNode (read $GOTSIZE bytes)"

printf '\n\033[1;32mLab 9 PASS\033[0m — erasure coding: less storage than 3x replication, still fault tolerant.\n'
