#!/usr/bin/env bash
# Lab 15 verification — Avro round-trip, codec sizes differ, and schema evolution reads old data.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
HS=hive-server
ROWS=100000

h() { $COMPOSE exec -T "$NN" "$@"; }
PRELUDE="SET hive.execution.engine=mr; SET mapreduce.framework.name=local; SET hive.exec.mode.local.auto=true;"
bee() { $COMPOSE exec -T "$HS" beeline -u jdbc:hive2://localhost:10000 -n root --silent=true -e "$PRELUDE $*"; }
count() { bee "$1" | grep -Eo '[0-9]+' | tail -n1; }
pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }
gen() { awk -v n="$1" 'BEGIN{split("AZ,TR,US,DE,FR",C,",");for(i=1;i<=n;i++)printf "%d,%s,%d.%02d\n",i,C[(i%5)+1],i%1000,i%100}'; }
firstfile() { h bash -c "hdfs dfs -ls -R $1 | awk '/^-/ {print \$8}' | head -n1" | tr -d '\r'; }
dusize() { h bash -c "hdfs dfs -du -s $1 | awk '{print \$1}'" | tr -d '\r'; }

echo "==> Lab 15 checks"

# 0) Metastore reachable + source table.
DBS=$(bee "SHOW DATABASES;")
grep -qw default <<<"$DBS" || fail "metastore did not return the 'default' database"
h hdfs dfs -mkdir -p /data/sales
gen "$ROWS" | h hdfs dfs -put -f - /data/sales/sales.csv
bee "DROP TABLE IF EXISTS sales_src;
     CREATE EXTERNAL TABLE sales_src (id INT, country STRING, amount DOUBLE)
       ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE LOCATION '/data/sales';" >/dev/null
[ "$(count 'SELECT count(*) FROM sales_src;')" = "$ROWS" ] || fail "source table row count wrong"
pass "metastore reachable, source table loaded ($ROWS rows)"

# 1) Avro table round-trips and its files carry the 'Obj' magic.
bee "DROP TABLE IF EXISTS sales_avro;
     CREATE TABLE sales_avro (id INT, country STRING, amount DOUBLE) STORED AS AVRO;
     INSERT INTO sales_avro SELECT * FROM sales_src;" >/dev/null
[ "$(count 'SELECT count(*) FROM sales_avro;')" = "$ROWS" ] || fail "avro table row count wrong"
AF=$(firstfile /user/hive/warehouse/sales_avro)
MAG=$(h bash -c "hdfs dfs -cat '$AF' 2>/dev/null | head -c 3; true")
[ "$MAG" = "Obj" ] || fail "avro file magic wrong (got '$MAG', expected 'Obj')"
pass "Avro table round-trips ($ROWS rows); files start with the 'Obj' magic"

# 2) GZIP vs SNAPPY — gzip stores fewer bytes for this data.
bee "DROP TABLE IF EXISTS sales_snappy;
     CREATE TABLE sales_snappy (id INT, country STRING, amount DOUBLE) STORED AS PARQUET
       TBLPROPERTIES ('parquet.compression'='SNAPPY');
     INSERT INTO sales_snappy SELECT * FROM sales_src;" >/dev/null
bee "DROP TABLE IF EXISTS sales_gzip;
     CREATE TABLE sales_gzip (id INT, country STRING, amount DOUBLE) STORED AS PARQUET
       TBLPROPERTIES ('parquet.compression'='GZIP');
     INSERT INTO sales_gzip SELECT * FROM sales_src;" >/dev/null
SN=$(dusize /user/hive/warehouse/sales_snappy)
GZ=$(dusize /user/hive/warehouse/sales_gzip)
[ -n "$SN" ] && [ -n "$GZ" ] || fail "could not read codec sizes (snappy=$SN gzip=$GZ)"
[ "$GZ" -lt "$SN" ] || fail "expected GZIP smaller than SNAPPY (gzip=$GZ snappy=$SN)"
pass "codec choice changes size (gzip=$GZ < snappy=$SN bytes)"

# 3) Schema evolution — add a column; existing rows read back NULL, no rewrite.
bee "DROP TABLE IF EXISTS sales_evo;
     CREATE TABLE sales_evo (id INT, country STRING, amount DOUBLE) STORED AS PARQUET;
     INSERT INTO sales_evo SELECT * FROM sales_src;" >/dev/null
bee "ALTER TABLE sales_evo ADD COLUMNS (note STRING);" >/dev/null
NULLS=$(count "SELECT count(*) FROM sales_evo WHERE note IS NULL;")
[ "$NULLS" = "$ROWS" ] || fail "expected all $ROWS existing rows to have NULL note, got $NULLS"
pass "schema evolution works — added column reads NULL for old rows (no rewrite)"

printf '\n\033[1;32mLab 15 PASS\033[0m — Avro/Parquet, codec trade-offs, and no-rewrite schema evolution.\n'
