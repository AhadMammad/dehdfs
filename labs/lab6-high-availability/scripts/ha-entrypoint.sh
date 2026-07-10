#!/usr/bin/env bash
# Lab 6 HA entrypoint. One script, dispatched by $HA_ROLE, drives the full HA lifecycle:
# journalnode / namenode (primary or standby) / datanode. It deliberately bypasses the
# bde2020 image's env-to-XML entrypoint and uses the explicit config mounted at /etc/hadoop.
set -euo pipefail

export HADOOP_CONF_DIR=${HADOOP_CONF_DIR:-/etc/hadoop}

# Wait until a TCP port is accepting connections (uses bash /dev/tcp — no netcat needed).
wait_port() {
	local host=$1 port=$2 tries=${3:-90}
	echo "   waiting for $host:$port ..."
	for _ in $(seq 1 "$tries"); do
		if (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then exec 3>&- 3<&-; echo "   $host:$port is up"; return 0; fi
		sleep 2
	done
	echo "!! timed out waiting for $host:$port" >&2; return 1
}

case "${HA_ROLE:?set HA_ROLE}" in

  journalnode)
	mkdir -p /hadoop/dfs/journal
	echo "==> starting JournalNode"
	exec hdfs journalnode
	;;

  namenode)
	: "${NN_ID:?set NN_ID (nn1|nn2)}"
	# The shared edit log lives on the JournalNodes, and failover needs ZooKeeper.
	wait_port jn1 8485; wait_port jn2 8485; wait_port jn3 8485
	wait_port zookeeper 2181

	if [ "$NN_ID" = "nn1" ]; then
		# Primary: format the namespace (and the shared journal) on first boot only.
		if [ ! -d /hadoop/dfs/name/current ]; then
			echo "==> [nn1] formatting namespace + shared edits"
			hdfs namenode -format -force -nonInteractive
			echo "==> [nn1] formatting the ZooKeeper failover znode"
			hdfs zkfc -formatZK -force -nonInteractive || true
		fi
	else
		# Standby: copy the namespace from the already-running primary on first boot only.
		if [ ! -d /hadoop/dfs/name/current ]; then
			echo "==> [nn2] waiting for the primary NameNode before bootstrapping"
			wait_port nn1 8020; wait_port nn1 9870
			echo "==> [nn2] bootstrapping standby from nn1"
			until hdfs namenode -bootstrapStandby -force -nonInteractive; do
				echo "   bootstrapStandby not ready yet, retrying..."; sleep 5
			done
		fi
	fi

	echo "==> [$NN_ID] starting ZKFC (failover controller) + NameNode"
	hdfs zkfc &            # watches ZooKeeper, promotes/demotes this NameNode
	exec hdfs namenode
	;;

  datanode)
	mkdir -p /hadoop/dfs/data
	wait_port nn1 8020 || true
	wait_port nn2 8020 || true
	echo "==> starting DataNode"
	exec hdfs datanode
	;;

  *)
	echo "unknown HA_ROLE=$HA_ROLE" >&2; exit 1
	;;
esac
