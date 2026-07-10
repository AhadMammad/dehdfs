#!/usr/bin/env bash
# Lab 6 verification — proves automatic NameNode failover with no data loss.
set -euo pipefail

COMPOSE="docker compose"

pass() { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

# Run an hdfs command from a specific (still-running) NameNode container.
on() { local c=$1; shift; $COMPOSE exec -T "$c" "$@"; }
state() { on "$1" hdfs haadmin -getServiceState "$1" 2>/dev/null | tr -d '\r'; }

echo "==> Lab 6 checks"

# 1) Exactly one NameNode is active and the other is standby.
S1=$(state nn1); S2=$(state nn2)
echo "   nn1=$S1  nn2=$S2"
ACTIVES=0; [ "$S1" = "active" ] && ACTIVES=$((ACTIVES+1)); [ "$S2" = "active" ] && ACTIVES=$((ACTIVES+1))
STANDBYS=0; [ "$S1" = "standby" ] && STANDBYS=$((STANDBYS+1)); [ "$S2" = "standby" ] && STANDBYS=$((STANDBYS+1))
[ "$ACTIVES" = "1" ] && [ "$STANDBYS" = "1" ] || fail "expected exactly 1 active + 1 standby (nn1=$S1 nn2=$S2)"
pass "HA is healthy: one active NameNode, one standby"

# Identify which is active / standby.
if [ "$S1" = "active" ]; then ACTIVE=nn1; STANDBY=nn2; else ACTIVE=nn2; STANDBY=nn1; fi

# 2) Write data through the nameservice while ACTIVE is up.
PAYLOAD="ha-survives-failover-$(date +%s)"
on "$ACTIVE" bash -c "hdfs dfs -mkdir -p /verify && echo '$PAYLOAD' | hdfs dfs -put -f - /verify/data.txt"
GOT=$(on "$ACTIVE" hdfs dfs -cat /verify/data.txt | tr -d '\r')
[ "$GOT" = "$PAYLOAD" ] || fail "write/read before failover mismatch"
pass "wrote data via the active NameNode ($ACTIVE)"

# 3) Kill the active NameNode.
echo "==> Stopping the active NameNode ($ACTIVE) to force a failover..."
$COMPOSE stop "$ACTIVE" >/dev/null
pass "stopped the active NameNode"

# 4) The standby must be promoted to active automatically.
echo "==> Waiting for automatic failover ($STANDBY -> active)..."
PROMOTED=0
for i in $(seq 1 45); do
	ST=$(state "$STANDBY" || true)
	printf '   %s=%s\n' "$STANDBY" "${ST:-?}"
	if [ "$ST" = "active" ]; then PROMOTED=1; break; fi
	sleep 3
done
[ "$PROMOTED" = "1" ] || fail "standby $STANDBY was not promoted to active in time"
pass "automatic failover happened: $STANDBY is now active"

# 5) Data written before the failover is still readable from the new active NN.
GOT2=$(on "$STANDBY" hdfs dfs -cat /verify/data.txt | tr -d '\r')
[ "$GOT2" = "$PAYLOAD" ] || fail "data unreadable/incorrect after failover (got '$GOT2')"
pass "pre-failover data is intact and served by the new active NameNode"

# 6) New writes succeed against the new active NN (cluster still fully writable).
on "$STANDBY" bash -c "echo 'after failover' | hdfs dfs -put -f - /verify/after.txt"
on "$STANDBY" hdfs dfs -test -e /verify/after.txt || fail "cluster not writable after failover"
pass "cluster remains writable after failover"

# 7) Bring the old NameNode back; it must rejoin as STANDBY (not a second active).
echo "==> Restarting $ACTIVE; it should rejoin as standby..."
$COMPOSE start "$ACTIVE" >/dev/null
REJOINED=0
for i in $(seq 1 30); do
	ST=$(state "$ACTIVE" || true)
	if [ "$ST" = "standby" ]; then REJOINED=1; break; fi
	sleep 3
done
[ "$REJOINED" = "1" ] || fail "$ACTIVE did not rejoin as standby (state=$(state "$ACTIVE" || echo '?'))"
pass "$ACTIVE rejoined as standby — one active, one standby again"

printf '\n\033[1;32mLab 6 PASS\033[0m — HA failover is automatic and data survives a NameNode loss.\n'
