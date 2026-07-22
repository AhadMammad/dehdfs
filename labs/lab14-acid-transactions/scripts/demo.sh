#!/usr/bin/env bash
# Lab 14 demo — Hive ACID: UPDATE/DELETE over immutable HDFS via delta files + compaction.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server
h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }
lsw() { h bash -c "hdfs dfs -ls -R /user/hive/warehouse/accounts 2>/dev/null | grep -iE 'delta|base' || true"; }

say "Create a TRANSACTIONAL ORC table (bucketed, as Hive 2.x ACID requires):"
bee "DROP TABLE IF EXISTS accounts;
     CREATE TABLE accounts (id INT, name STRING, balance INT)
       CLUSTERED BY (id) INTO 2 BUCKETS
       STORED AS ORC TBLPROPERTIES ('transactional'='true');"

say "INSERT some rows:"
bee "INSERT INTO accounts VALUES (1,'alice',100),(2,'bob',200),(3,'carol',300),(4,'dan',400),(5,'eve',500);"
bee "SELECT * FROM accounts ORDER BY id;"

say "UPDATE and DELETE — impossible on a plain HDFS table, but fine here:"
bee "UPDATE accounts SET balance = 999 WHERE id = 2;"
bee "DELETE FROM accounts WHERE id = 4;"
bee "SELECT * FROM accounts ORDER BY id;"

say "On disk those changes are layered delta files over the base (nothing was rewritten in place):"
lsw

say "Run a MAJOR compaction to merge the deltas into a fresh base:"
bee "ALTER TABLE accounts COMPACT 'major';"
echo "waiting for the compactor to produce a base_ directory..."
for i in $(seq 1 24); do
	if h bash -c "hdfs dfs -ls -R /user/hive/warehouse/accounts 2>/dev/null | grep -qi '/base_'"; then break; fi
	sleep 5
done
lsw

printf '\n\033[1;32mDemo complete.\033[0m ACID tables give you UPDATE/DELETE via deltas, then compaction merges them.\n'
