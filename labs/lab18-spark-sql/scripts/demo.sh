#!/usr/bin/env bash
# Lab 18 demo — Spark SQL reads the Hive tables from HDFS, and writes one Hive can read back.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server
SP=spark
ROWS=100000

h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
sq() { $COMPOSE exec -T "$SP" /opt/spark/bin/spark-sql -e "$*" 2>/dev/null; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }
gen() { awk -v n="$1" 'BEGIN{split("AZ,TR,US,DE,FR",C,",");for(i=1;i<=n;i++)printf "%d,%s,%d.%02d\n",i,C[(i%5)+1],i%1000,i%100}'; }

say "Build a Parquet table with HIVE (local MapReduce), as in lab 7:"
h hdfs dfs -mkdir -p /data/sales
gen "$ROWS" | h hdfs dfs -put -f - /data/sales/sales.csv
bee "DROP TABLE IF EXISTS sales_src;
     CREATE EXTERNAL TABLE sales_src (id INT, country STRING, amount DOUBLE)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE LOCATION '/data/sales';
     DROP TABLE IF EXISTS sales_parquet;
     CREATE TABLE sales_parquet (id INT, country STRING, amount DOUBLE) STORED AS PARQUET;
     INSERT INTO sales_parquet SELECT * FROM sales_src;"

say "Spark shares the metastore — it sees the same tables:"
sq "SHOW TABLES"

say "Query the SAME Parquet files with Spark SQL (a different engine entirely):"
sq "SELECT count(*) AS n FROM sales_parquet"
sq "SELECT country, sum(amount) AS total FROM sales_parquet GROUP BY country ORDER BY country"

say "Now WRITE a table with Spark — and watch Hive read it back (shared metastore + HDFS):"
sq "DROP TABLE IF EXISTS spark_summary;
    CREATE TABLE spark_summary STORED AS PARQUET AS
      SELECT country, count(*) AS n, sum(amount) AS total FROM sales_parquet GROUP BY country"
echo "Hive reading the Spark-created table:"
bee "SELECT * FROM spark_summary ORDER BY country;"

printf '\n\033[1;32mDemo complete.\033[0m Spark and Hive share one metastore + HDFS — either engine reads the other'\''s tables.\n'
