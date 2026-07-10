#!/usr/bin/env bash
# Lab 4 demo — the NameNode's metadata: fsimage, the edit log, safemode, and checkpointing.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
DIR=/hadoop/dfs/name/current
h() { $COMPOSE exec -T "$NN" "$@"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }

say "The NameNode keeps ALL namespace metadata in one directory on disk:"
h ls -1 "$DIR"
echo "  fsimage_*  = a checkpoint (snapshot) of the whole namespace"
echo "  edits_*    = the edit log: every change since the last checkpoint"
echo "  seen_txid  = the latest transaction id the NameNode has seen"

say "Make some namespace changes. Each one is appended to the edit log:"
h hdfs dfs -mkdir -p /demo/a /demo/b /demo/c
h hdfs dfs -touchz /demo/a/f1 /demo/b/f2
echo "current in-progress edit log:"
h bash -c "ls -l $DIR/edits_inprogress_* 2>/dev/null || true"

say "Enter SAFEMODE. In safemode the namespace is READ-ONLY (no writes allowed):"
h hdfs dfsadmin -safemode enter
h hdfs dfsadmin -safemode get
echo "Try to write while in safemode (this is expected to FAIL):"
h hdfs dfs -touchz /demo/should-fail 2>&1 | grep -i "safe mode" || true

say "Force a CHECKPOINT with saveNamespace: merge the edit log into a fresh fsimage:"
echo "fsimage files BEFORE:"; h bash -c "ls -1 $DIR | grep -E '^fsimage_[0-9]+$'"
h hdfs dfsadmin -saveNamespace
echo "fsimage files AFTER (note the new, higher transaction id):"; h bash -c "ls -1 $DIR | grep -E '^fsimage_[0-9]+$'"

say "Leave safemode — writes are allowed again:"
h hdfs dfsadmin -safemode leave
h hdfs dfsadmin -safemode get

say "Inspect the fsimage with the Offline Image Viewer (oiv) — metadata as XML:"
LATEST=$(h bash -c "ls -1 $DIR | grep -E '^fsimage_[0-9]+$' | sort | tail -1")
h bash -c "hdfs oiv -i $DIR/$LATEST -o /tmp/fsimage.xml -p XML && echo '--- first inode entries ---' && grep -o '<name>[^<]*</name>' /tmp/fsimage.xml | head"

printf '\n\033[1;32mDemo complete.\033[0m fsimage=snapshot, edits=journal, checkpoint=merge of the two.\n'
