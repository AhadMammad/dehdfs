#!/usr/bin/env bash
# Lab 16 verification — DROP deletes managed data, keeps external data.
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

echo "==> Lab 16 checks"

# 0) Metastore reachable.
DBS=$(bee "SHOW DATABASES;")
grep -qw default <<<"$DBS" || fail "metastore did not return the 'default' database"
pass "Hive metastore reachable"

# Setup: external data + one managed + one external table.
h hdfs dfs -mkdir -p /data/ext
h bash -c "printf '1,alice\n2,bob\n' | hdfs dfs -put -f - /data/ext/people.csv"
bee "DROP TABLE IF EXISTS managed_people;
     CREATE TABLE managed_people (id INT, name STRING) ROW FORMAT DELIMITED FIELDS TERMINATED BY ',';
     INSERT INTO managed_people VALUES (1,'alice'),(2,'bob');" >/dev/null
bee "DROP TABLE IF EXISTS ext_people;
     CREATE EXTERNAL TABLE ext_people (id INT, name STRING)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' LOCATION '/data/ext';" >/dev/null

# 1) Both tables have the 2 rows.
[ "$(count 'SELECT count(*) FROM managed_people;')" = "2" ] || fail "managed_people row count wrong"
[ "$(count 'SELECT count(*) FROM ext_people;')" = "2" ] || fail "ext_people row count wrong"
h hdfs dfs -test -e /user/hive/warehouse/managed_people || fail "managed data dir missing before DROP"
pass "managed + external tables both created with 2 rows"

# 2) DROP managed -> HDFS data deleted.
bee "DROP TABLE managed_people;" >/dev/null
if h hdfs dfs -test -e /user/hive/warehouse/managed_people >/dev/null 2>&1; then
	fail "managed table data still in HDFS after DROP"
fi
pass "DROP managed_people deleted its HDFS data"

# 3) DROP external -> HDFS files remain.
bee "DROP TABLE ext_people;" >/dev/null
h hdfs dfs -test -e /data/ext/people.csv >/dev/null 2>&1 \
	|| fail "external table data was deleted from HDFS after DROP"
pass "DROP ext_people kept its HDFS data (/data/ext/people.csv still there)"

printf '\n\033[1;32mLab 16 PASS\033[0m — managed DROP deletes data; external DROP keeps it.\n'
