#!/usr/bin/env bash
# Lab 17 verification — Trino reads the same Hive/HDFS tables and agrees with Hive.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server
TR=trino
ROWS=100000

h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
tr_q() { $COMPOSE exec -T "$TR" trino --catalog hive --schema default --output-format CSV_UNQUOTED --execute "$*"; }
hcount() { bee "$1" | grep -Eo '[0-9]+' | tail -n1; }
tcount() { tr_q "$1" | grep -Eo '[0-9]+' | tail -n1; }
pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }
gen() { awk -v n="$1" 'BEGIN{split("AZ,TR,US,DE,FR",C,",");for(i=1;i<=n;i++)printf "%d,%s,%d.%02d\n",i,C[(i%5)+1],i%1000,i%100}'; }

echo "==> Lab 17 checks"

# 1) Trino is up and answering queries.
[ "$(tcount 'SELECT 1')" = "1" ] || fail "Trino did not answer SELECT 1"
pass "Trino engine is up (SELECT 1)"

# 2) Build a Parquet table with Hive.
h hdfs dfs -mkdir -p /data/sales
gen "$ROWS" | h hdfs dfs -put -f - /data/sales/sales.csv
bee "DROP TABLE IF EXISTS sales_src;
     CREATE EXTERNAL TABLE sales_src (id INT, country STRING, amount DOUBLE)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE LOCATION '/data/sales';
     DROP TABLE IF EXISTS sales_parquet;
     CREATE TABLE sales_parquet (id INT, country STRING, amount DOUBLE) STORED AS PARQUET;
     INSERT INTO sales_parquet SELECT * FROM sales_src;" >/dev/null
[ "$(hcount 'SELECT count(*) FROM sales_parquet;')" = "$ROWS" ] || fail "Hive built the table with the wrong row count"
pass "Hive built sales_parquet ($ROWS rows)"

# 3) Trino sees the table through the shared metastore.
tr_q "SHOW TABLES" | grep -q 'sales_parquet' || fail "Trino does not see sales_parquet in the hive catalog"
pass "Trino sees sales_parquet via the shared metastore"

# 4) Trino's count matches Hive's — same files, different engine.
TC=$(tcount 'SELECT count(*) FROM sales_parquet')
[ "$TC" = "$ROWS" ] || fail "Trino count ($TC) != expected $ROWS"
pass "Trino count matches ($TC rows) — it read the same HDFS Parquet files"

# 5) A Trino GROUP BY returns the 5 countries.
GROUPS=$(tr_q "SELECT country FROM sales_parquet GROUP BY country" | grep -cE '^[A-Z][A-Z]$' || true)
[ "$GROUPS" = "5" ] || fail "expected 5 country groups from Trino, got $GROUPS"
pass "Trino GROUP BY returned 5 countries"

printf '\n\033[1;32mLab 17 PASS\033[0m — Trino queried the Hive tables straight from HDFS, no MapReduce.\n'
