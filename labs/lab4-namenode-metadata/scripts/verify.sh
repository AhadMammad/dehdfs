#!/usr/bin/env bash
# Lab 4 verification — proves safemode behaviour and that a checkpoint writes a new fsimage.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
DIR=/hadoop/dfs/name/current
h() { $COMPOSE exec -T "$NN" "$@"; }

pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

# Highest fsimage transaction id currently on disk.
max_fsimage_txid() {
	h bash -c "ls -1 $DIR | grep -E '^fsimage_[0-9]+\$' | sed -E 's/fsimage_0*([0-9]+)/\\1/' | sort -n | tail -1"
}

echo "==> Lab 4 checks"

# 0) The metadata files exist where we say they do.
h bash -c "ls $DIR/fsimage_* >/dev/null 2>&1" || fail "no fsimage found in $DIR"
h bash -c "ls $DIR/seen_txid >/dev/null 2>&1" || fail "no seen_txid found in $DIR"
pass "NameNode metadata (fsimage + seen_txid) present in $DIR"

# 1) Make sure we start OUT of safemode.
h hdfs dfsadmin -safemode leave >/dev/null 2>&1 || true
h hdfs dfsadmin -safemode get | grep -q "Safe mode is OFF" || fail "expected safemode OFF at start"
pass "safemode is OFF initially"

# 2) Grow the edit log with some namespace changes.
h hdfs dfs -mkdir -p /verify/a /verify/b
h hdfs dfs -touchz /verify/a/f1
pass "made namespace changes (appended to the edit log)"

# 3) Enter safemode -> get reports ON.
h hdfs dfsadmin -safemode enter >/dev/null
h hdfs dfsadmin -safemode get | grep -q "Safe mode is ON" || fail "safemode did not turn ON"
pass "safemode toggled ON"

# 4) Writes are rejected while in safemode.
if h hdfs dfs -touchz /verify/should-fail >/dev/null 2>&1; then
	fail "a write SUCCEEDED while in safemode (it should have been rejected)"
fi
pass "writes are rejected while in safemode (namespace is read-only)"

# 5) saveNamespace forces a checkpoint -> a new fsimage with a HIGHER txid.
BEFORE=$(max_fsimage_txid); BEFORE=${BEFORE:-0}
h hdfs dfsadmin -saveNamespace >/dev/null
AFTER=$(max_fsimage_txid); AFTER=${AFTER:-0}
[ "$AFTER" -gt "$BEFORE" ] || fail "checkpoint did not advance the fsimage txid ($BEFORE -> $AFTER)"
pass "checkpoint wrote a new fsimage (txid $BEFORE -> $AFTER)"

# 6) Leave safemode -> writes work again.
h hdfs dfsadmin -safemode leave >/dev/null
h hdfs dfsadmin -safemode get | grep -q "Safe mode is OFF" || fail "safemode did not turn OFF"
h hdfs dfs -touchz /verify/b/after-checkpoint || fail "write failed after leaving safemode"
pass "safemode toggled OFF and writes resumed"

printf '\n\033[1;32mLab 4 PASS\033[0m — fsimage/edits, safemode, and checkpointing behave as designed.\n'
