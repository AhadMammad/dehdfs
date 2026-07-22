#!/usr/bin/env bash
# Lab 13 verification — a bucketed table produces N bucket files and supports sampling.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server
ROWS=100000
BUCKETS=8

h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true; SET hive.enforce.bucketing=true;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
count() { bee "$1" | grep -Eo '[0-9]+' | tail -n1; }
pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }
gen() { awk -v n="$1" 'BEGIN{split("AZ,TR,US,DE,FR",C,",");for(i=1;i<=n;i++)printf "%d,%s,%d.%02d\n",i,C[(i%5)+1],i%1000,i%100}'; }

echo "==> Lab 13 checks"

# 0) Metastore reachable.
DBS=$(bee "SHOW DATABASES;")
grep -qw default <<<"$DBS" || fail "metastore did not return the 'default' database"
pass "Hive metastore reachable"

# 1) Source table over a generated CSV.
h hdfs dfs -mkdir -p /data/sales
gen "$ROWS" | h hdfs dfs -put -f - /data/sales/sales.csv
bee "DROP TABLE IF EXISTS sales_src;
     CREATE EXTERNAL TABLE sales_src (id INT, country STRING, amount DOUBLE)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE LOCATION '/data/sales';" >/dev/null
[ "$(count 'SELECT count(*) FROM sales_src;')" = "$ROWS" ] || fail "sales_src row count wrong"
pass "source table loaded ($ROWS rows)"

# 2) Bucketed table with N buckets.
bee "DROP TABLE IF EXISTS sales_bucketed;
     CREATE TABLE sales_bucketed (id INT, country STRING, amount DOUBLE)
       CLUSTERED BY (id) INTO $BUCKETS BUCKETS STORED AS PARQUET;
     INSERT INTO sales_bucketed SELECT * FROM sales_src;" >/dev/null
[ "$(count 'SELECT count(*) FROM sales_bucketed;')" = "$ROWS" ] || fail "sales_bucketed row count wrong"
pass "bucketed table loaded ($ROWS rows)"

# 3) Exactly N bucket files in HDFS.
FILES=$(h bash -c "hdfs dfs -ls /user/hive/warehouse/sales_bucketed | awk '/^-/' | wc -l" | tr -d '\r ')
[ "$FILES" = "$BUCKETS" ] || fail "expected $BUCKETS bucket files, found $FILES"
pass "table stored as exactly $BUCKETS bucket files in HDFS"

# 4) Sampling one bucket returns a fraction of the rows (roughly 1/N).
ONE=$(count "SELECT count(*) FROM sales_bucketed TABLESAMPLE(BUCKET 1 OUT OF $BUCKETS ON id);")
[ -n "$ONE" ] || fail "sampling query returned nothing"
[ "$ONE" -gt 0 ] && [ "$ONE" -lt "$ROWS" ] || fail "bucket sample ($ONE) not a proper subset of $ROWS"
EIGHTH=$((ROWS / BUCKETS))
[ "$ONE" -gt $((EIGHTH / 2)) ] && [ "$ONE" -lt $((EIGHTH * 2)) ] \
	|| fail "bucket sample ($ONE) far from the expected ~$EIGHTH"
pass "TABLESAMPLE(BUCKET 1 OUT OF $BUCKETS) returned $ONE rows (~1/$BUCKETS of $ROWS)"

printf '\n\033[1;32mLab 13 PASS\033[0m — bucketing hashed the data into %s files and enabled sampling.\n' "$BUCKETS"
