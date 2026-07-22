#!/usr/bin/env bash
# Lab 13 demo — bucketing hashes a column into a fixed number of files.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server
ROWS=100000
BUCKETS=8

h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true; SET hive.enforce.bucketing=true;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }
gen() { awk -v n="$1" 'BEGIN{split("AZ,TR,US,DE,FR",C,",");for(i=1;i<=n;i++)printf "%d,%s,%d.%02d\n",i,C[(i%5)+1],i%1000,i%100}'; }

say "Land a $ROWS-row CSV and read it with a plain source table:"
h hdfs dfs -mkdir -p /data/sales
gen "$ROWS" | h hdfs dfs -put -f - /data/sales/sales.csv
bee "DROP TABLE IF EXISTS sales_src;
     CREATE EXTERNAL TABLE sales_src (id INT, country STRING, amount DOUBLE)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE LOCATION '/data/sales';"

say "Create a table CLUSTERED BY (id) INTO $BUCKETS BUCKETS and load it:"
bee "DROP TABLE IF EXISTS sales_bucketed;
     CREATE TABLE sales_bucketed (id INT, country STRING, amount DOUBLE)
       CLUSTERED BY (id) INTO $BUCKETS BUCKETS STORED AS PARQUET;
     INSERT INTO sales_bucketed SELECT * FROM sales_src;"

say "Each bucket is its own file in HDFS — expect $BUCKETS of them:"
h hdfs dfs -ls /user/hive/warehouse/sales_bucketed

say "Bucketing powers cheap sampling — read just 1 of the $BUCKETS buckets:"
bee "SELECT count(*) AS one_bucket FROM sales_bucketed TABLESAMPLE(BUCKET 1 OUT OF $BUCKETS ON id);"
bee "SELECT count(*) AS total FROM sales_bucketed;"

printf '\n\033[1;32mDemo complete.\033[0m Bucketing spreads rows across a fixed set of files by hashing a column.\n'
