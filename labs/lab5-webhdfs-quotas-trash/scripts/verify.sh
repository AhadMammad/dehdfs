#!/usr/bin/env bash
# Lab 5 verification — WebHDFS round-trip, quota enforcement, and trash behaviour.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
h() { $COMPOSE exec -T "$NN" "$@"; }
BASE="http://namenode:9870/webhdfs/v1"

pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

echo "==> Lab 5 checks"

# 1) WebHDFS create + read round-trip returns identical content.
PAYLOAD="webhdfs-roundtrip-payload"
h bash -c "echo '$PAYLOAD' > /tmp/w.txt"
h curl -s -X PUT "$BASE/verify?op=MKDIRS" >/dev/null
CODE=$(h bash -c "curl -s -L -X PUT -T /tmp/w.txt '$BASE/verify/hello.txt?op=CREATE&overwrite=true' -o /dev/null -w '%{http_code}'")
[ "$CODE" = "201" ] || fail "WebHDFS CREATE returned HTTP $CODE (expected 201)"
GOT=$(h bash -c "curl -s -L '$BASE/verify/hello.txt?op=OPEN'" | tr -d '\r')
[ "$GOT" = "$PAYLOAD" ] || fail "WebHDFS OPEN mismatch: expected '$PAYLOAD', got '$GOT'"
pass "WebHDFS CREATE+OPEN round-trip preserved content over HTTP"

# 2) LISTSTATUS returns JSON that includes the file.
h bash -c "curl -s '$BASE/verify?op=LISTSTATUS'" | grep -q '"pathSuffix":"hello.txt"' \
	|| fail "WebHDFS LISTSTATUS did not list hello.txt"
pass "WebHDFS LISTSTATUS returned the file as JSON"

# 3) NAME QUOTA: a dir capped at 3 inodes rejects the 3rd child.
h hdfs dfs -mkdir -p /verify/nq
h hdfs dfsadmin -setQuota 3 /verify/nq
h hdfs dfs -touchz /verify/nq/f1
h hdfs dfs -touchz /verify/nq/f2
if h hdfs dfs -touchz /verify/nq/f3 >/dev/null 2>&1; then
	fail "name quota not enforced (3rd file was allowed)"
fi
pass "name quota enforced (3rd inode rejected)"

# 4) SPACE QUOTA: a 1 MiB-capped dir rejects a 5 MiB file.
h hdfs dfs -mkdir -p /verify/sq
h hdfs dfsadmin -setSpaceQuota 1m /verify/sq
h bash -c 'dd if=/dev/zero of=/tmp/big.bin bs=1M count=5 status=none'
if h hdfs dfs -put -f /tmp/big.bin /verify/sq/big.bin >/dev/null 2>&1; then
	fail "space quota not enforced (5 MiB file fit in a 1 MiB quota)"
fi
pass "space quota enforced (over-quota write rejected)"

# 5) TRASH: 'rm' (without -skipTrash) moves the file into .Trash.
h hdfs dfs -rm /verify/hello.txt >/dev/null 2>&1
if ! h bash -c "hdfs dfs -ls -R /user 2>/dev/null | grep -q 'Trash.*hello.txt'"; then
	fail "removed file did not land in .Trash"
fi
pass "rm moved the file to .Trash (recoverable)"

# 6) -skipTrash bypasses the trash (file is gone, not in .Trash).
h hdfs dfs -touchz /verify/perm.txt
h hdfs dfs -rm -skipTrash /verify/perm.txt >/dev/null 2>&1
if h bash -c "hdfs dfs -ls -R /user 2>/dev/null | grep -q 'Trash.*perm.txt'"; then
	fail "-skipTrash file unexpectedly landed in .Trash"
fi
pass "-skipTrash deleted immediately (no trash copy)"

printf '\n\033[1;32mLab 5 PASS\033[0m — WebHDFS REST, quotas, and trash all behave as designed.\n'
