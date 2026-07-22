#!/usr/bin/env bash
# Lab 11 verification — permissions deny a user, an ACL grants exactly that user.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
h() { $COMPOSE exec -T "$NN" "$@"; }
as() { local u=$1; shift; h bash -c "HADOOP_USER_NAME=$u $*"; }
pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

echo "==> Lab 11 checks"

# Setup: /proj owned by alice, mode 750, with a file in it (done as the superuser).
h hdfs dfs -mkdir -p /proj
h hdfs dfs -chown alice:alice /proj
h hdfs dfs -chmod 750 /proj
h hdfs dfs -touchz /proj/data.txt

# 1) bob is denied by the POSIX bits (not owner, not in group).
if as bob "hdfs dfs -ls /proj" >/dev/null 2>&1; then
	fail "bob could access /proj with mode 750 and no ACL"
fi
pass "bob denied by POSIX permissions (mode 750)"

# 2) Grant bob r-x via an extended ACL, and getfacl shows it.
h hdfs dfs -setfacl -m user:bob:r-x /proj >/dev/null
h bash -c "hdfs dfs -getfacl /proj" | grep -q 'user:bob:r-x' \
	|| fail "getfacl does not show the user:bob:r-x entry"
pass "ACL user:bob:r-x added (getfacl shows it)"

# 3) bob can now access /proj.
if ! as bob "hdfs dfs -ls /proj" >/dev/null 2>&1; then
	fail "bob still denied after the ACL was granted"
fi
pass "bob can access /proj via the ACL"

# 4) carol, with no ACL entry, is still denied — ACLs are user-specific.
if as carol "hdfs dfs -ls /proj" >/dev/null 2>&1; then
	fail "carol accessed /proj without any grant"
fi
pass "carol (no ACL) is still denied — the grant is user-specific"

printf '\n\033[1;32mLab 11 PASS\033[0m — POSIX permissions deny, and an ACL grants exactly one named user.\n'
