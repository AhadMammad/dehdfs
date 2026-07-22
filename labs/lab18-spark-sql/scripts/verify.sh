#!/usr/bin/env bash
# Lab 18 verification — Spark reads Hive tables and writes one Hive can read back.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server
SP=spark
ROWS=100000

h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
hcount() { bee "$1" | grep -Eo '[0-9]+' | tail -n1; }
# Spark logs are noisy; tag the value so we can extract it cleanly from stdout.
sqtag() { $COMPOSE exec -T "$SP" /opt/spark/bin/spark-sql -e "$1" 2>/dev/null | grep -oE 'TAG[0-9]+' | head -n1 | sed 's/TAG//'; }
pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }
gen() { awk -v n="$1" 'BEGIN{split("AZ,TR,US,DE,FR",C,",");for(i=1;i<=n;i++)printf "%d,%s,%d.%02d\n",i,C[(i%5)+1],i%1000,i%100}'; }

echo "==> Lab 18 checks"

# 1) Spark SQL is up and answers a query.
[ "$(sqtag "SELECT concat('TAG', cast(1 as string))")" = "1" ] || fail "Spark SQL did not answer a basic query"
pass "Spark SQL engine is up"

# 2) Build a Parquet table with Hive.
h hdfs dfs -mkdir -p /data/sales
gen "$ROWS" | h hdfs dfs -put -f - /data/sales/sales.csv
bee "DROP TABLE IF EXISTS sales_src;
     CREATE EXTERNAL TABLE sales_src (id INT, country STRING, amount DOUBLE)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE LOCATION '/data/sales';
     DROP TABLE IF EXISTS sales_parquet;
     CREATE TABLE sales_parquet (id INT, country STRING, amount DOUBLE) STORED AS PARQUET;
     INSERT INTO sales_parquet SELECT * FROM sales_src;" >/dev/null
[ "$(hcount 'SELECT count(*) FROM sales_parquet;')" = "$ROWS" ] || fail "Hive built the table with the wrong count"
pass "Hive built sales_parquet ($ROWS rows)"

# 3) Spark reads the same table and its count matches Hive's.
SC=$(sqtag "SELECT concat('TAG', cast(count(*) as string)) FROM sales_parquet")
[ "$SC" = "$ROWS" ] || fail "Spark count ($SC) != expected $ROWS"
pass "Spark read the same table ($SC rows) — shared metastore + HDFS"

# 4) Spark writes a table; Hive reads it back (5 countries).
$COMPOSE exec -T "$SP" /opt/spark/bin/spark-sql -e \
	"DROP TABLE IF EXISTS spark_summary; CREATE TABLE spark_summary STORED AS PARQUET AS
	 SELECT country, count(*) AS n FROM sales_parquet GROUP BY country" >/dev/null 2>&1
HC=$(hcount 'SELECT count(*) FROM spark_summary;')
[ "$HC" = "5" ] || fail "Hive did not read the Spark-created table correctly (got $HC, expected 5)"
pass "Spark-written table is readable by Hive (5 country rows)"

printf '\n\033[1;32mLab 18 PASS\033[0m — Spark and Hive interoperate over one metastore + HDFS.\n'
