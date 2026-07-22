#!/usr/bin/env bash
# Lab 17 demo — Trino queries the SAME Hive tables from HDFS, with no MapReduce.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server
TR=trino
ROWS=100000

h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
tr_q() { $COMPOSE exec -T "$TR" trino --catalog hive --schema default --output-format ALIGNED --execute "$*"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }
gen() { awk -v n="$1" 'BEGIN{split("AZ,TR,US,DE,FR",C,",");for(i=1;i<=n;i++)printf "%d,%s,%d.%02d\n",i,C[(i%5)+1],i%1000,i%100}'; }

say "Build a Parquet table with HIVE (local MapReduce), exactly like lab 7:"
h hdfs dfs -mkdir -p /data/sales
gen "$ROWS" | h hdfs dfs -put -f - /data/sales/sales.csv
bee "DROP TABLE IF EXISTS sales_src;
     CREATE EXTERNAL TABLE sales_src (id INT, country STRING, amount DOUBLE)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE LOCATION '/data/sales';
     DROP TABLE IF EXISTS sales_parquet;
     CREATE TABLE sales_parquet (id INT, country STRING, amount DOUBLE) STORED AS PARQUET;
     INSERT INTO sales_parquet SELECT * FROM sales_src;"

say "Trino sees the same catalog — list the tables via the metastore:"
tr_q "SHOW TABLES"

say "Now query the SAME Parquet files with Trino — no YARN, no MapReduce, interactive speed:"
tr_q "SELECT count(*) AS n FROM sales_parquet"
tr_q "SELECT country, sum(amount) AS total FROM sales_parquet GROUP BY country ORDER BY country"

say "Same storage, different engine: Hive and Trino read the identical HDFS files."

printf '\n\033[1;32mDemo complete.\033[0m Trino ran SQL over the Hive tables straight from HDFS — engine != storage.\n'
