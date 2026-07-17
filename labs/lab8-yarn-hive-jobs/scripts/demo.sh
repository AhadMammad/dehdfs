#!/usr/bin/env bash
# Lab 8 demo — the same partitioned CSV/Parquet/ORC build as Lab 7, at 10M rows, run on YARN.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server
RM=resourcemanager

# Lab 8 runs on YARN (a real cluster), so it handles the full 10M rows.
ROWS=10000000
NDATES=5
PER=$((ROWS / NDATES))

h()  { $COMPOSE exec -T "$NN" "$@"; }   # hdfs commands
yr() { $COMPOSE exec -T "$RM" "$@"; }   # yarn commands (on the ResourceManager)
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=yarn; SET hive.exec.mode.local.auto=false;"
DP="SET hive.exec.dynamic.partition=true; SET hive.exec.dynamic.partition.mode=nonstrict;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }

gen_part() {
  awk -v k="$1" -v per="$2" 'BEGIN{
    split("AZ,TR,US,DE,FR",C,",");split("books,food,tech",K,",");
    base=(k-1)*per;
    for(i=1;i<=per;i++){id=base+i;printf "%d,%s,%s,%d.%02d\n",id,C[(id%5)+1],K[(id%3)+1],id%1000,id%100}
  }'
}

say "Two NodeManagers are ready to run work:"
yr yarn node -list 2>/dev/null || true

say "Generate $ROWS rows of CSV, laid out as one HDFS directory per day (dt=YYYY-MM-DD):"
for k in $(seq 1 "$NDATES"); do
  d=$(printf "2026-01-%02d" "$k")
  h hdfs dfs -mkdir -p "/data/sales/dt=$d"
  gen_part "$k" "$PER" | h hdfs dfs -put -f - "/data/sales/dt=$d/data.csv"
  echo "  wrote /data/sales/dt=$d/data.csv ($PER rows)"
done
h hdfs dfs -ls /data/sales

say "1) CSV — a PARTITIONED external table over those directories (MSCK REPAIR registers partitions):"
bee "DROP TABLE IF EXISTS sales_csv;
     CREATE EXTERNAL TABLE sales_csv (id INT, country STRING, category STRING, amount DOUBLE)
       PARTITIONED BY (dt STRING)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
       STORED AS TEXTFILE
       LOCATION '/data/sales';
     MSCK REPAIR TABLE sales_csv;"

say "2) & 3) Parquet and ORC copies, also partitioned by dt. Each INSERT is a YARN job — watch :8088"
bee "DROP TABLE IF EXISTS sales_parquet;
     CREATE TABLE sales_parquet (id INT, country STRING, category STRING, amount DOUBLE)
       PARTITIONED BY (dt STRING) STORED AS PARQUET;
     $DP
     INSERT INTO sales_parquet PARTITION (dt) SELECT id, country, category, amount, dt FROM sales_csv;"
bee "DROP TABLE IF EXISTS sales_orc;
     CREATE TABLE sales_orc (id INT, country STRING, category STRING, amount DOUBLE)
       PARTITIONED BY (dt STRING) STORED AS ORC;
     $DP
     INSERT INTO sales_orc PARTITION (dt) SELECT id, country, category, amount, dt FROM sales_csv;"

say "Every table is partitioned — one dt=... subdirectory per day in HDFS:"
h hdfs dfs -ls /user/hive/warehouse/sales_parquet
h hdfs dfs -ls /user/hive/warehouse/sales_orc
PFILE=$(h bash -c "hdfs dfs -ls -R /user/hive/warehouse/sales_parquet | awk '/^-/ {print \$8}' | head -n1" | tr -d '\r')
OFILE=$(h bash -c "hdfs dfs -ls -R /user/hive/warehouse/sales_orc | awk '/^-/ {print \$8}' | head -n1" | tr -d '\r')
h bash -c "echo -n 'parquet: '; hdfs dfs -cat '$PFILE' 2>/dev/null | head -c 4; echo; true"
h bash -c "echo -n 'orc:     '; hdfs dfs -cat '$OFILE' 2>/dev/null | head -c 3; echo; true"

say "Compare on-disk size — columnar compresses far better than raw CSV:"
h hdfs dfs -du -h -s /data/sales /user/hive/warehouse/sales_parquet /user/hive/warehouse/sales_orc

say "All those loads ran on the cluster — here they are in YARN's finished-application list:"
yr yarn application -list -appStates FINISHED 2>/dev/null || true

printf '\n\033[1;32mDemo complete.\033[0m Same partitioned CSV/Parquet/ORC build as Lab 7 (%s rows) — every load run by YARN.\n' "$ROWS"
