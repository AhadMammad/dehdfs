#!/usr/bin/env bash
# Lab 11 demo — POSIX permissions plus extended ACLs decide who can touch a path.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
h() { $COMPOSE exec -T "$NN" "$@"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }
# Run an hdfs command as a specific (non-superuser) HDFS user.
as() { local u=$1; shift; h bash -c "HADOOP_USER_NAME=$u $*"; }

say "Permission checks are ENABLED in this lab. As the superuser, make /proj owned by alice, mode 750:"
h hdfs dfs -mkdir -p /proj
h hdfs dfs -chown alice:alice /proj
h hdfs dfs -chmod 750 /proj
h hdfs dfs -touchz /proj/data.txt
h hdfs dfs -ls -d /proj

say "bob is neither the owner nor in the group, so 'other' has no access — bob is denied:"
as bob "hdfs dfs -ls /proj" 2>&1 | grep -i 'Permission denied' || true

say "Grant bob read+execute with an extended ACL:"
h hdfs dfs -setfacl -m user:bob:r-x /proj
h hdfs dfs -getfacl /proj

say "Now bob can list the directory:"
as bob "hdfs dfs -ls /proj" && echo "bob can access /proj"

say "But carol, who has no ACL entry, is still denied — ACLs are per-user:"
as carol "hdfs dfs -ls /proj" 2>&1 | grep -i 'Permission denied' || true

printf '\n\033[1;32mDemo complete.\033[0m POSIX bits gate the owner/group/other; ACLs grant extra named users.\n'
