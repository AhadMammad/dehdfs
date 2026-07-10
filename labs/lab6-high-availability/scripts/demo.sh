#!/usr/bin/env bash
# Lab 6 demo — kill the ACTIVE NameNode and watch the standby take over automatically.
set -euo pipefail

COMPOSE="docker compose"
CLIENT=nn1
h() { $COMPOSE exec -T "$CLIENT" "$@"; }
say() { printf '\n\033[1;34m# %s\033[0m\n' "$*"; }

active_nn() {
	for n in nn1 nn2; do
		if [ "$($COMPOSE exec -T "$CLIENT" hdfs haadmin -getServiceState "$n" 2>/dev/null | tr -d '\r')" = "active" ]; then
			echo "$n"; return 0
		fi
	done
	return 1
}

say "Current state of both NameNodes (one active, one standby):"
h hdfs haadmin -getAllServiceState || true

say "Write a file through the logical nameservice 'hdfs://mycluster':"
h hdfs dfs -mkdir -p /demo
h bash -c 'echo "written before failover" | hdfs dfs -put -f - /demo/before.txt'
h hdfs dfs -cat /demo/before.txt

ACTIVE=$(active_nn); echo ""; echo "Active NameNode is: $ACTIVE"

say "Now KILL the active NameNode container ($ACTIVE) — a simulated machine failure:"
$COMPOSE stop "$ACTIVE"

say "ZKFC notices the ZooKeeper session drop and promotes the standby. Watching..."
for i in $(seq 1 30); do
	OTHER=$([ "$ACTIVE" = "nn1" ] && echo nn2 || echo nn1)
	ST=$($COMPOSE exec -T "$OTHER" hdfs haadmin -getServiceState "$OTHER" 2>/dev/null | tr -d '\r' || true)
	printf '  t=%2ds  %s=%s\n' "$((i*3))" "$OTHER" "${ST:-?}"
	[ "$ST" = "active" ] && { echo "  -> $OTHER is now ACTIVE. Failover complete."; break; }
	sleep 3
done

say "The data written before the failover is still readable (served by the new active NN):"
OTHER=$([ "$ACTIVE" = "nn1" ] && echo nn2 || echo nn1)
$COMPOSE exec -T "$OTHER" hdfs dfs -cat /demo/before.txt

say "Bring the old NameNode back — it rejoins as the STANDBY:"
$COMPOSE start "$ACTIVE"

printf '\n\033[1;32mDemo complete.\033[0m The cluster survived losing a NameNode with no downtime for data.\n'
