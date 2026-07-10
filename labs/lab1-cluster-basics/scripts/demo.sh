#!/usr/bin/env bash
# Lab 1 demo — a narrated tour of the HDFS shell against a 1-NameNode/1-DataNode cluster.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
# Run an hdfs command inside the NameNode container.
h() { $COMPOSE exec -T "$NN" "$@"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }

say "Who is in the cluster? (NameNode + DataNodes, capacity, live nodes)"
h hdfs dfsadmin -report | head -n 20 || true

say "The namespace starts basically empty. Make a directory tree:"
h hdfs dfs -mkdir -p /demo/input
h hdfs dfs -ls -R /demo

say "Create a local file and PUT it into HDFS:"
h bash -c 'echo "hello hdfs — the file lives as blocks on the DataNode" > /tmp/hello.txt'
h hdfs dfs -put -f /tmp/hello.txt /demo/input/hello.txt

say "List it, then CAT it back out of HDFS:"
h hdfs dfs -ls /demo/input
h hdfs dfs -cat /demo/input/hello.txt

say "GET it back to a local path and diff — round-trip should be identical:"
h bash -c 'hdfs dfs -get -f /demo/input/hello.txt /tmp/hello.copy && diff /tmp/hello.txt /tmp/hello.copy && echo "round-trip OK"'

say "Space accounting: -du (per path) and -df (whole filesystem):"
h hdfs dfs -du -h /demo
h hdfs dfs -df -h /

say "tail the file, then remove it:"
h hdfs dfs -tail /demo/input/hello.txt
h hdfs dfs -rm -f /demo/input/hello.txt
h hdfs dfs -ls /demo/input

printf '\n\033[1;32mDemo complete.\033[0m Explore the NameNode UI at http://localhost:9870\n'
