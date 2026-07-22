#!/usr/bin/env bash
# Lab 14 verification — ACID UPDATE/DELETE work and compaction merges deltas into a base.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server
h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
count() { bee "$1" | grep -Eo '[0-9]+' | tail -n1; }
pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

echo "==> Lab 14 checks"

# 0) Metastore reachable.
DBS=$(bee "SHOW DATABASES;")
grep -qw default <<<"$DBS" || fail "metastore did not return the 'default' database"
pass "Hive metastore reachable"

# 1) Create a transactional table and insert 5 rows.
bee "DROP TABLE IF EXISTS accounts;
     CREATE TABLE accounts (id INT, name STRING, balance INT)
       CLUSTERED BY (id) INTO 2 BUCKETS STORED AS ORC TBLPROPERTIES ('transactional'='true');
     INSERT INTO accounts VALUES (1,'alice',100),(2,'bob',200),(3,'carol',300),(4,'dan',400),(5,'eve',500);" >/dev/null
[ "$(count 'SELECT count(*) FROM accounts;')" = "5" ] || fail "expected 5 rows after INSERT"
pass "transactional ORC table created with 5 rows"

# 2) UPDATE changes a row in place (logically).
bee "UPDATE accounts SET balance = 999 WHERE id = 2;" >/dev/null
[ "$(count 'SELECT balance FROM accounts WHERE id = 2;')" = "999" ] || fail "UPDATE did not take effect"
pass "UPDATE changed id=2 balance to 999"

# 3) DELETE removes a row.
bee "DELETE FROM accounts WHERE id = 4;" >/dev/null
[ "$(count 'SELECT count(*) FROM accounts;')" = "4" ] || fail "DELETE did not reduce the row count to 4"
[ "$(count 'SELECT count(*) FROM accounts WHERE id = 4;')" = "0" ] || fail "row id=4 still present after DELETE"
pass "DELETE removed id=4 (4 rows remain)"

# 4) The mutations are stored as delta files.
h bash -c "hdfs dfs -ls -R /user/hive/warehouse/accounts 2>/dev/null | grep -qi 'delta'" \
	|| fail "no delta files found for the transactional table"
pass "mutations are stored as delta files in HDFS"

# 5) Major compaction merges deltas into a base directory.
bee "ALTER TABLE accounts COMPACT 'major';" >/dev/null
COMPACTED=0
for i in $(seq 1 24); do
	if h bash -c "hdfs dfs -ls -R /user/hive/warehouse/accounts 2>/dev/null | grep -qi '/base_'"; then COMPACTED=1; break; fi
	sleep 5
done
[ "$COMPACTED" = "1" ] || fail "compaction did not produce a base_ directory in time"
# Data is unchanged after compaction.
[ "$(count 'SELECT count(*) FROM accounts;')" = "4" ] || fail "row count changed after compaction"
[ "$(count 'SELECT balance FROM accounts WHERE id = 2;')" = "999" ] || fail "value changed after compaction"
pass "major compaction merged deltas into a base_ directory (data intact)"

printf '\n\033[1;32mLab 14 PASS\033[0m — ACID UPDATE/DELETE via deltas, merged by compaction.\n'
