#!/usr/bin/env bash
# Lab 7 demo — one dataset stored as partitioned CSV, Parquet and ORC tables in HDFS.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server

# Lab 7 runs local-mode MapReduce (no cluster), so keep the dataset modest.
# (Lab 8 runs the same build on YARN with 10x the rows.)
ROWS=1000000
NDATES=5
PER=$((ROWS / NDATES))

h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true;"
DP="SET hive.exec.dynamic.partition=true; SET hive.exec.dynamic.partition.mode=nonstrict;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }

# Emit `per` rows for date-partition k. dt comes from the directory, so it is NOT in the file.
gen_part() {
  awk -v k="$1" -v per="$2" 'BEGIN{
    split("AZ,TR,US,DE,FR",C,",");split("books,food,tech",K,",");
    base=(k-1)*per;
    for(i=1;i<=per;i++){id=base+i;printf "%d,%s,%s,%d.%02d\n",id,C[(id%5)+1],K[(id%3)+1],id%1000,id%100}
  }'
}

say "Generate $ROWS rows of CSV, laid out as one HDFS directory per day (dt=YYYY-MM-DD):"
for k in $(seq 1 "$NDATES"); do
  d=$(printf "2026-01-%02d" "$k")
  h hdfs dfs -mkdir -p "/data/sales/dt=$d"
  gen_part "$k" "$PER" | h hdfs dfs -put -f - "/data/sales/dt=$d/data.csv"
  echo "  wrote /data/sales/dt=$d/data.csv ($PER rows)"
done
h hdfs dfs -ls /data/sales

say "1) CSV — a PARTITIONED external table over those directories. MSCK REPAIR registers the partitions:"
bee "DROP TABLE IF EXISTS sales_csv;
     CREATE EXTERNAL TABLE sales_csv (id INT, country STRING, category STRING, amount DOUBLE)
       PARTITIONED BY (dt STRING)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
       STORED AS TEXTFILE
       LOCATION '/data/sales';
     MSCK REPAIR TABLE sales_csv;"
bee "SHOW PARTITIONS sales_csv;"
bee "SELECT count(*) AS n FROM sales_csv;"

say "2) Parquet — same rows, columnar, also partitioned by dt (dynamic-partition INSERT):"
bee "DROP TABLE IF EXISTS sales_parquet;
     CREATE TABLE sales_parquet (id INT, country STRING, category STRING, amount DOUBLE)
       PARTITIONED BY (dt STRING) STORED AS PARQUET;
     $DP
     INSERT INTO sales_parquet PARTITION (dt) SELECT id, country, category, amount, dt FROM sales_csv;"

say "3) ORC — same rows, a different columnar format, also partitioned by dt:"
bee "DROP TABLE IF EXISTS sales_orc;
     CREATE TABLE sales_orc (id INT, country STRING, category STRING, amount DOUBLE)
       PARTITIONED BY (dt STRING) STORED AS ORC;
     $DP
     INSERT INTO sales_orc PARTITION (dt) SELECT id, country, category, amount, dt FROM sales_csv;"

say "Every table is partitioned — one dt=... subdirectory per day in HDFS:"
h hdfs dfs -ls /user/hive/warehouse/sales_parquet
h hdfs dfs -ls /user/hive/warehouse/sales_orc

say "Prove the columnar files by their magic numbers (Parquet='PAR1', ORC='ORC'):"
PFILE=$(h bash -c "hdfs dfs -ls -R /user/hive/warehouse/sales_parquet | awk '/^-/ {print \$8}' | head -n1" | tr -d '\r')
OFILE=$(h bash -c "hdfs dfs -ls -R /user/hive/warehouse/sales_orc | awk '/^-/ {print \$8}' | head -n1" | tr -d '\r')
h bash -c "echo -n 'parquet: '; hdfs dfs -cat '$PFILE' 2>/dev/null | head -c 4; echo; true"
h bash -c "echo -n 'orc:     '; hdfs dfs -cat '$OFILE' 2>/dev/null | head -c 3; echo; true"

say "Compare on-disk size — columnar compresses far better than raw CSV:"
h hdfs dfs -du -h -s /data/sales /user/hive/warehouse/sales_parquet /user/hive/warehouse/sales_orc

say "Partition pruning — this query only needs to read the dt=2026-01-03 directory:"
bee "SELECT count(*) AS n FROM sales_parquet WHERE dt='2026-01-03';"

printf '\n\033[1;32mDemo complete.\033[0m One dataset as partitioned CSV/Parquet/ORC tables in HDFS.\n'
