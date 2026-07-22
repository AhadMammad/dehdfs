#!/usr/bin/env bash
# Lab 16 demo — managed tables own their data; external tables own only metadata.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server
h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }
exists() { h bash -c "hdfs dfs -test -e '$1' && echo EXISTS || echo GONE" | tr -d '\r'; }

say "Land a CSV in HDFS at /data/ext to back an EXTERNAL table:"
h hdfs dfs -mkdir -p /data/ext
h bash -c "printf '1,alice\n2,bob\n' | hdfs dfs -put -f - /data/ext/people.csv"

say "A MANAGED table — Hive owns the data (it lives under the warehouse):"
bee "DROP TABLE IF EXISTS managed_people;
     CREATE TABLE managed_people (id INT, name STRING) ROW FORMAT DELIMITED FIELDS TERMINATED BY ',';
     INSERT INTO managed_people VALUES (1,'alice'),(2,'bob');"
h hdfs dfs -ls /user/hive/warehouse/managed_people

say "An EXTERNAL table — Hive owns only the schema; the data stays at /data/ext:"
bee "DROP TABLE IF EXISTS ext_people;
     CREATE EXTERNAL TABLE ext_people (id INT, name STRING)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' LOCATION '/data/ext';"
bee "SELECT count(*) AS n FROM managed_people;"
bee "SELECT count(*) AS n FROM ext_people;"

say "DROP the MANAGED table — its HDFS data is deleted with it:"
bee "DROP TABLE managed_people;"
echo "warehouse/managed_people -> $(exists /user/hive/warehouse/managed_people)"

say "DROP the EXTERNAL table — the HDFS files are left untouched:"
bee "DROP TABLE ext_people;"
echo "/data/ext/people.csv -> $(exists /data/ext/people.csv)"

printf '\n\033[1;32mDemo complete.\033[0m DROP deletes a managed table'\''s data, but leaves an external table'\''s data in place.\n'
