#!/usr/bin/env bash
# Lab 15 demo — Avro alongside Parquet/ORC, compression codecs, and schema evolution.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server
ROWS=100000

h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }
gen() { awk -v n="$1" 'BEGIN{split("AZ,TR,US,DE,FR",C,",");for(i=1;i<=n;i++)printf "%d,%s,%d.%02d\n",i,C[(i%5)+1],i%1000,i%100}'; }
firstfile() { h bash -c "hdfs dfs -ls -R $1 | awk '/^-/ {print \$8}' | head -n1" | tr -d '\r'; }

say "Load a $ROWS-row source table from CSV:"
h hdfs dfs -mkdir -p /data/sales
gen "$ROWS" | h hdfs dfs -put -f - /data/sales/sales.csv
bee "DROP TABLE IF EXISTS sales_src;
     CREATE EXTERNAL TABLE sales_src (id INT, country STRING, amount DOUBLE)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE LOCATION '/data/sales';"

say "AVRO — a row-oriented, schema-carrying format. Its files begin with the magic 'Obj':"
bee "DROP TABLE IF EXISTS sales_avro;
     CREATE TABLE sales_avro (id INT, country STRING, amount DOUBLE) STORED AS AVRO;
     INSERT INTO sales_avro SELECT * FROM sales_src;"
AF=$(firstfile /user/hive/warehouse/sales_avro)
h bash -c "echo -n 'avro magic: '; hdfs dfs -cat '$AF' 2>/dev/null | head -c 3; echo; true"

say "Same data, Parquet with two compression codecs — GZIP squeezes harder than SNAPPY:"
bee "DROP TABLE IF EXISTS sales_snappy;
     CREATE TABLE sales_snappy (id INT, country STRING, amount DOUBLE) STORED AS PARQUET
       TBLPROPERTIES ('parquet.compression'='SNAPPY');
     INSERT INTO sales_snappy SELECT * FROM sales_src;"
bee "DROP TABLE IF EXISTS sales_gzip;
     CREATE TABLE sales_gzip (id INT, country STRING, amount DOUBLE) STORED AS PARQUET
       TBLPROPERTIES ('parquet.compression'='GZIP');
     INSERT INTO sales_gzip SELECT * FROM sales_src;"
h hdfs dfs -du -s -v /user/hive/warehouse/sales_snappy /user/hive/warehouse/sales_gzip

say "SCHEMA EVOLUTION — add a column to an existing Parquet table WITHOUT rewriting old files:"
bee "DROP TABLE IF EXISTS sales_evo;
     CREATE TABLE sales_evo (id INT, country STRING, amount DOUBLE) STORED AS PARQUET;
     INSERT INTO sales_evo SELECT * FROM sales_src;"
bee "ALTER TABLE sales_evo ADD COLUMNS (note STRING);"
echo "Existing rows simply read back NULL for the new 'note' column (no data rewritten):"
bee "SELECT id, country, note FROM sales_evo ORDER BY id LIMIT 3;"

printf '\n\033[1;32mDemo complete.\033[0m One dataset, many formats/codecs — and columns can be added without a rewrite.\n'
