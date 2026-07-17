#!/usr/bin/env bash
# Show what the Hive Metastore persists in its PostgreSQL database: databases, tables,
# storage formats, HDFS locations, columns, partition keys and partition values.
# The table DATA lives in HDFS — only this *metadata* lives here.
set -euo pipefail

COMPOSE="docker compose"
MDB=hive-metastore-postgresql

# Run a query against the metastore DB. Hive's schema uses mixed-case, quoted identifiers,
# so the SQL quotes them with double quotes; keep each -c argument in single quotes.
# (Connect over TCP as the 'hive' user the metastore itself uses; password is 'hive'.)
pg() { $COMPOSE exec -T -e PGPASSWORD=hive "$MDB" psql -h 127.0.0.1 -U hive -d metastore -P pager=off "$@"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }

say "Databases the metastore knows about (DBS):"
pg -c 'SELECT "NAME", "DB_LOCATION_URI" FROM "DBS" ORDER BY "NAME";'

say "Tables and their type (TBLS + DBS):"
pg -c 'SELECT d."NAME" AS db, t."TBL_NAME", t."TBL_TYPE"
       FROM "TBLS" t JOIN "DBS" d ON t."DB_ID" = d."DB_ID"
       ORDER BY d."NAME", t."TBL_NAME";'

say "Each table's storage format + HDFS location (TBLS + SDS):"
pg -c 'SELECT t."TBL_NAME", s."INPUT_FORMAT", s."LOCATION"
       FROM "TBLS" t JOIN "SDS" s ON t."SD_ID" = s."SD_ID"
       ORDER BY t."TBL_NAME";'

say "Columns per table (TBLS -> SDS -> CDS -> COLUMNS_V2):"
pg -c 'SELECT t."TBL_NAME", c."INTEGER_IDX" AS idx, c."COLUMN_NAME", c."TYPE_NAME"
       FROM "TBLS" t JOIN "SDS" s ON t."SD_ID" = s."SD_ID"
       JOIN "COLUMNS_V2" c ON s."CD_ID" = c."CD_ID"
       ORDER BY t."TBL_NAME", c."INTEGER_IDX";'

say "Partition keys (PARTITION_KEYS) — dt is metadata, NOT a column in the data files:"
pg -c 'SELECT t."TBL_NAME", pk."PKEY_NAME", pk."PKEY_TYPE"
       FROM "TBLS" t JOIN "PARTITION_KEYS" pk ON t."TBL_ID" = pk."TBL_ID"
       ORDER BY t."TBL_NAME", pk."INTEGER_IDX";'

say "Registered partitions (PARTITIONS) — one row per dt=... directory in HDFS:"
pg -c 'SELECT t."TBL_NAME", p."PART_NAME"
       FROM "PARTITIONS" p JOIN "TBLS" t ON p."TBL_ID" = t."TBL_ID"
       ORDER BY t."TBL_NAME", p."PART_NAME";'

say "How much metadata is stored in the key tables:"
pg -c 'SELECT (SELECT count(*) FROM "DBS")         AS dbs,
              (SELECT count(*) FROM "TBLS")        AS tbls,
              (SELECT count(*) FROM "COLUMNS_V2")  AS columns,
              (SELECT count(*) FROM "PARTITION_KEYS") AS partition_keys,
              (SELECT count(*) FROM "PARTITIONS")  AS partitions;'

printf '\n\033[1;32mThat is everything the metastore persists.\033[0m The table DATA itself lives in HDFS — this database only maps names/schemas/partitions to HDFS locations.\n'
