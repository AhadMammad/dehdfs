#!/usr/bin/env bash
# Lab 1 verification — proves basic HDFS read/write works end-to-end.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
h() { $COMPOSE exec -T "$NN" "$@"; }

pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

echo "==> Lab 1 checks"

# 1) The cluster reports at least one live DataNode.
LIVE=$(h hdfs dfsadmin -report 2>/dev/null | grep -c 'Name: ' || true)
[ "$LIVE" -ge 1 ] || fail "expected >=1 live DataNode, found $LIVE"
pass "cluster has $LIVE live DataNode(s)"

# 2) mkdir creates a namespace path.
h hdfs dfs -mkdir -p /verify
h hdfs dfs -test -d /verify || fail "directory /verify was not created"
pass "mkdir created /verify"

# 3) put + cat round-trip preserves content exactly.
CONTENT="dehdfs-lab1-$(date +%s)-payload"
h bash -c "echo '$CONTENT' > /tmp/v.txt && hdfs dfs -put -f /tmp/v.txt /verify/v.txt"
h hdfs dfs -test -e /verify/v.txt || fail "/verify/v.txt does not exist after put"
GOT=$(h hdfs dfs -cat /verify/v.txt | tr -d '\r')
[ "$GOT" = "$CONTENT" ] || fail "cat mismatch: expected '$CONTENT', got '$GOT'"
pass "put/cat round-trip preserved content"

# 4) ls shows the file.
h hdfs dfs -ls /verify | grep -q '/verify/v.txt' || fail "ls did not list /verify/v.txt"
pass "ls lists the file"

# 5) rm removes it.
h hdfs dfs -rm -f -skipTrash /verify/v.txt >/dev/null
if h hdfs dfs -test -e /verify/v.txt; then fail "file still exists after rm"; fi
pass "rm removed the file"

printf '\n\033[1;32mLab 1 PASS\033[0m — NameNode/DataNode + FS shell work.\n'
