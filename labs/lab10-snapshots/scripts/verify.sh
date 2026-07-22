#!/usr/bin/env bash
# Lab 10 verification — a snapshot preserves and recovers a deleted file.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
h() { $COMPOSE exec -T "$NN" "$@"; }
pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

PAYLOAD="snapshot-original-payload"

echo "==> Lab 10 checks"

# 1) Create a file and snapshot the directory.
h hdfs dfs -mkdir -p /data
h bash -c "echo '$PAYLOAD' | hdfs dfs -put -f - /data/report.txt"
h hdfs dfsadmin -allowSnapshot /data >/dev/null
h hdfs dfs -createSnapshot /data snap1 >/dev/null
pass "created snapshot snap1 of /data"

# 2) Delete the file from the live directory.
h hdfs dfs -rm -skipTrash /data/report.txt >/dev/null 2>&1
if h hdfs dfs -test -e /data/report.txt >/dev/null 2>&1; then
	fail "report.txt still present in the live directory after delete"
fi
pass "deleted /data/report.txt from the live directory"

# 3) snapshotDiff reports the deletion since snap1.
DIFF=$(h bash -c "hdfs snapshotDiff /data snap1 . 2>/dev/null" || true)
grep -q 'report.txt' <<<"$DIFF" || fail "snapshotDiff did not report the deleted file"
pass "snapshotDiff reports the change since snap1"

# 4) The deleted file still exists in the snapshot, byte-for-byte.
h hdfs dfs -test -e /data/.snapshot/snap1/report.txt >/dev/null 2>&1 \
	|| fail "report.txt missing from the snapshot"
GOT=$(h bash -c "hdfs dfs -cat /data/.snapshot/snap1/report.txt" | tr -d '\r')
[ "$GOT" = "$PAYLOAD" ] || fail "snapshot content mismatch (got '$GOT')"
pass "deleted file still recoverable from .snapshot/snap1 (identical content)"

# 5) Restore it from the snapshot.
h hdfs dfs -cp /data/.snapshot/snap1/report.txt /data/report.txt >/dev/null
GOT2=$(h bash -c "hdfs dfs -cat /data/report.txt" | tr -d '\r')
[ "$GOT2" = "$PAYLOAD" ] || fail "restore from snapshot failed (got '$GOT2')"
pass "restored the file from the snapshot"

printf '\n\033[1;32mLab 10 PASS\033[0m — snapshots preserve a point in time and recover deleted files.\n'
