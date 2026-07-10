#!/usr/bin/env bash
# Lab 3 demo — kill a DataNode and watch HDFS heal itself back to full replication.
set -euo pipefail

COMPOSE="docker compose"
NN=namenode
VICTIM=datanode4
h() { $COMPOSE exec -T "$NN" "$@"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }
live() { h hdfs dfsadmin -report 2>/dev/null | grep -a 'Live datanodes' | grep -oE '[0-9]+' | head -1; }
under() { h hdfs fsck / 2>/dev/null | grep -a 'Under-replicated blocks' | grep -oE '[0-9]+' | head -1; }

say "Start with 4 live DataNodes and write a replicated file:"
h bash -c 'dd if=/dev/zero of=/tmp/data.bin bs=1M count=8 status=none'
h hdfs dfs -mkdir -p /demo
h hdfs dfs -put -f /tmp/data.bin /demo/data.bin
echo "Live datanodes: $(live)  |  Under-replicated blocks: $(under)"

say "Record the file checksum so we can confirm the data survives:"
CKSUM_BEFORE=$(h hdfs dfs -checksum /demo/data.bin | awk '{print $2}')
echo "checksum = $CKSUM_BEFORE"

say "Now KILL one DataNode ($VICTIM):"
$COMPOSE stop "$VICTIM"

say "The NameNode declares it dead after ~60s (tuned timings). Watching recovery..."
for i in $(seq 1 60); do
	L=$(live); U=$(under)
	printf '  t=%3ds  live=%s  under-replicated=%s\n' "$((i*5))" "${L:-?}" "${U:-?}"
	if [ "${L:-9}" = "3" ] && [ "${U:-9}" = "0" ]; then
		echo "  -> node declared dead AND all blocks re-replicated onto the survivors."
		break
	fi
	sleep 5
done

say "Confirm the data is intact (checksum unchanged) even though a node was lost:"
CKSUM_AFTER=$(h hdfs dfs -checksum /demo/data.bin | awk '{print $2}')
echo "before=$CKSUM_BEFORE"
echo "after =$CKSUM_AFTER"
[ "$CKSUM_BEFORE" = "$CKSUM_AFTER" ] && echo "  -> identical: no data lost."

say "Restart the node; it rejoins and the cluster rebalances:"
$COMPOSE start "$VICTIM"

printf '\n\033[1;32mDemo complete.\033[0m HDFS survived a node failure with no data loss.\n'
