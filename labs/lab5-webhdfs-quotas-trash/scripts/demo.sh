#!/usr/bin/env bash
# Lab 5 demo — talk to HDFS over the WebHDFS REST API, then explore quotas and the trash.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
# Run inside the NameNode container so 'namenode'/'datanode' hostnames resolve for WebHDFS redirects.
h() { $COMPOSE exec -T "$NN" "$@"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }
BASE="http://namenode:9870/webhdfs/v1"

say "WebHDFS = the HDFS filesystem over plain HTTP. Make a directory via REST:"
h curl -s -X PUT "$BASE/web?op=MKDIRS"; echo

say "CREATE a file over HTTP (PUT follows a 307 redirect to the DataNode):"
h bash -c "echo 'hello from WebHDFS' > /tmp/w.txt && curl -s -L -X PUT -T /tmp/w.txt '$BASE/web/hello.txt?op=CREATE&overwrite=true' -o /dev/null -w 'HTTP %{http_code}\n'"

say "OPEN (read) it back over HTTP:"
h curl -s -L "$BASE/web/hello.txt?op=OPEN"; echo

say "LISTSTATUS the directory as JSON:"
h curl -s "$BASE/web?op=LISTSTATUS"; echo

say "NAME QUOTA: limit a directory to at most 3 inodes (itself + 2 entries):"
h hdfs dfs -mkdir -p /web/limited
h hdfs dfsadmin -setQuota 3 /web/limited
h hdfs dfs -touchz /web/limited/f1
h hdfs dfs -touchz /web/limited/f2
echo "Third file should FAIL (quota exceeded):"
h hdfs dfs -touchz /web/limited/f3 2>&1 | grep -i quota || true

say "SPACE QUOTA: cap a directory at 1 MiB, then try to write 5 MiB into it:"
h hdfs dfs -mkdir -p /web/small
h hdfs dfsadmin -setSpaceQuota 1m /web/small
h bash -c 'dd if=/dev/zero of=/tmp/big.bin bs=1M count=5 status=none'
echo "This put should FAIL (space quota exceeded):"
h hdfs dfs -put -f /tmp/big.bin /web/small/big.bin 2>&1 | grep -i quota || true
h hdfs dfs -count -q -h /web/small

say "TRASH: fs.trash.interval>0, so 'rm' MOVES files to .Trash instead of deleting them:"
h hdfs dfs -rm /web/hello.txt
echo "The file now lives under the user's .Trash:"
h bash -c "hdfs dfs -ls -R /user 2>/dev/null | grep -i 'Trash.*hello.txt' || true"
echo "Use -skipTrash for immediate, unrecoverable deletion:"
h hdfs dfs -rm -skipTrash /web/limited/f1 2>&1 | grep -i deleted || true

printf '\n\033[1;32mDemo complete.\033[0m REST access, quotas, and the trash safety net.\n'
