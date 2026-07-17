#!/usr/bin/env bash
# Lab 7 verification — one dataset as partitioned CSV, Parquet and ORC tables in HDFS.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server

# Lab 7 is local-mode MapReduce (no cluster), so it runs a modest 1M rows. (Lab 8 does 10M on YARN.)
ROWS=1000000
NDATES=5
PER=$((ROWS / NDATES))

h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true;"
DP="SET hive.exec.dynamic.partition=true; SET hive.exec.dynamic.partition.mode=nonstrict;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
count() { bee "$1" | grep -Eo '[0-9]+' | tail -n1; }   # grep -Eo reads to EOF (pipefail-safe)

pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

gen_part() {
  awk -v k="$1" -v per="$2" 'BEGIN{
    split("AZ,TR,US,DE,FR",C,",");split("books,food,tech",K,",");
    base=(k-1)*per;
    for(i=1;i<=per;i++){id=base+i;printf "%d,%s,%s,%d.%02d\n",id,C[(id%5)+1],K[(id%3)+1],id%1000,id%100}
  }'
}

echo "==> Lab 7 checks ($ROWS rows, $NDATES partitions)"

# 1) The metastore is reachable. Capture first, then match (piping beeline into `grep -q`
#    races: grep exits on match, beeline gets SIGPIPE, and pipefail turns success into failure).
DBS=$(bee "SHOW DATABASES;")
grep -qw default <<<"$DBS" || fail "metastore did not return the 'default' database"
pass "Hive metastore reachable (SHOW DATABASES lists 'default')"

# 2) Generate a partitioned CSV dataset (one HDFS dir per dt) and register it with an
#    external, partitioned table via MSCK REPAIR.
for k in $(seq 1 "$NDATES"); do
  d=$(printf "2026-01-%02d" "$k")
  h hdfs dfs -mkdir -p "/data/sales/dt=$d"
  gen_part "$k" "$PER" | h hdfs dfs -put -f - "/data/sales/dt=$d/data.csv"
done
h hdfs dfs -test -e /data/sales/dt=2026-01-01/data.csv || fail "partitioned CSV not found in HDFS"
bee "DROP TABLE IF EXISTS sales_csv;
     CREATE EXTERNAL TABLE sales_csv (id INT, country STRING, category STRING, amount DOUBLE)
       PARTITIONED BY (dt STRING)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE LOCATION '/data/sales';
     MSCK REPAIR TABLE sales_csv;" >/dev/null
NCSV=$(count "SELECT count(*) FROM sales_csv;")
[ "$NCSV" = "$ROWS" ] || fail "sales_csv has $NCSV rows, expected $ROWS"
CP=$(bee "SHOW PARTITIONS sales_csv;" | grep -c 'dt=' || true)
[ "$CP" = "$NDATES" ] || fail "sales_csv has $CP partitions, expected $NDATES"
pass "partitioned CSV in HDFS: $NDATES dt partitions, $ROWS rows"

# 3) Parquet copy — partitioned by dt, columnar; a data file starts with 'PAR1'.
bee "DROP TABLE IF EXISTS sales_parquet;
     CREATE TABLE sales_parquet (id INT, country STRING, category STRING, amount DOUBLE)
       PARTITIONED BY (dt STRING) STORED AS PARQUET;
     $DP
     INSERT INTO sales_parquet PARTITION (dt) SELECT id, country, category, amount, dt FROM sales_csv;" >/dev/null
NPQ=$(count "SELECT count(*) FROM sales_parquet;")
[ "$NPQ" = "$ROWS" ] || fail "sales_parquet has $NPQ rows, expected $ROWS"
PP=$(bee "SHOW PARTITIONS sales_parquet;" | grep -c 'dt=' || true)
[ "$PP" = "$NDATES" ] || fail "sales_parquet has $PP partitions, expected $NDATES"
PFILE=$(h bash -c "hdfs dfs -ls -R /user/hive/warehouse/sales_parquet | awk '/^-/ {print \$8}' | head -n1" | tr -d '\r')
PMAG=$(h bash -c "hdfs dfs -cat '$PFILE' 2>/dev/null | head -c 4; true")
[ "$PMAG" = "PAR1" ] || fail "sales_parquet file is not Parquet (first 4 bytes '$PMAG', expected 'PAR1')"
pass "sales_parquet: partitioned ($NDATES), $ROWS rows, Parquet files (PAR1)"

# 4) ORC copy — partitioned by dt, columnar; a data file starts with 'ORC'.
bee "DROP TABLE IF EXISTS sales_orc;
     CREATE TABLE sales_orc (id INT, country STRING, category STRING, amount DOUBLE)
       PARTITIONED BY (dt STRING) STORED AS ORC;
     $DP
     INSERT INTO sales_orc PARTITION (dt) SELECT id, country, category, amount, dt FROM sales_csv;" >/dev/null
NORC=$(count "SELECT count(*) FROM sales_orc;")
[ "$NORC" = "$ROWS" ] || fail "sales_orc has $NORC rows, expected $ROWS"
OP=$(bee "SHOW PARTITIONS sales_orc;" | grep -c 'dt=' || true)
[ "$OP" = "$NDATES" ] || fail "sales_orc has $OP partitions, expected $NDATES"
OFILE=$(h bash -c "hdfs dfs -ls -R /user/hive/warehouse/sales_orc | awk '/^-/ {print \$8}' | head -n1" | tr -d '\r')
OMAG=$(h bash -c "hdfs dfs -cat '$OFILE' 2>/dev/null | head -c 3; true")
[ "$OMAG" = "ORC" ] || fail "sales_orc file is not ORC (first 3 bytes '$OMAG', expected 'ORC')"
pass "sales_orc: partitioned ($NDATES), $ROWS rows, ORC files (ORC)"

# 5) Same data, three encodings.
{ [ "$NCSV" = "$NPQ" ] && [ "$NPQ" = "$NORC" ]; } || fail "row counts differ (csv=$NCSV parquet=$NPQ orc=$NORC)"
pass "same data in three partitioned formats (csv=parquet=orc=$ROWS)"

# 6) Partition pruning — a single-partition query reads only its dt=... directory.
DIRS=$(h bash -c "hdfs dfs -ls /user/hive/warehouse/sales_parquet | grep -c 'dt=' || true" | tr -d '\r')
[ "$DIRS" -ge "$NDATES" ] || fail "expected >=$NDATES dt= directories in HDFS, found $DIRS"
NONE=$(count "SELECT count(*) FROM sales_parquet WHERE dt='2026-01-03';")
[ "$NONE" = "$PER" ] || fail "dt=2026-01-03 has $NONE rows, expected $PER"
pass "partition pruning works (dt=2026-01-03 = $PER rows; $NDATES dirs in HDFS)"

printf '\n\033[1;32mLab 7 PASS\033[0m — one dataset as partitioned CSV/Parquet/ORC tables in HDFS.\n'
