#!/usr/bin/env bash
# Lab 10 demo — snapshots: a cheap, read-only point-in-time image of a directory.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
h() { $COMPOSE exec -T "$NN" "$@"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }

say "Create /data with a couple of files:"
h hdfs dfs -mkdir -p /data
h bash -c "echo 'v1 important report' | hdfs dfs -put -f - /data/report.txt"
h bash -c "echo 'keep me' | hdfs dfs -put -f - /data/keep.txt"
h hdfs dfs -ls /data

say "Enable snapshots on /data, then take a snapshot called snap1:"
h hdfs dfsadmin -allowSnapshot /data
h hdfs dfs -createSnapshot /data snap1

say "Now make a 'mistake' — delete report.txt and overwrite keep.txt:"
h hdfs dfs -rm -skipTrash /data/report.txt
h bash -c "echo 'OOPS overwritten' | hdfs dfs -put -f - /data/keep.txt"
h hdfs dfs -ls /data

say "The snapshot is read-only and still holds the originals under /data/.snapshot/snap1:"
h hdfs dfs -ls /data/.snapshot/snap1
echo "report.txt from the snapshot:"
h hdfs dfs -cat /data/.snapshot/snap1/report.txt

say "What changed since snap1? snapshotDiff shows it (+ added, - deleted, M modified):"
h hdfs snapshotDiff /data snap1 . || true

say "Restore the deleted file straight from the snapshot:"
h hdfs dfs -cp /data/.snapshot/snap1/report.txt /data/report.txt
h hdfs dfs -cat /data/report.txt

printf '\n\033[1;32mDemo complete.\033[0m A snapshot froze /data in time — deleted files stayed recoverable.\n'
