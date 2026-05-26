#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

pass() {
  echo "[PASS] $1"
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

need docker

echo "[INFO] Starting regression test at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

docker compose config -q || fail "docker compose config invalid"
pass "compose config valid"

docker compose up -d wazuh.indexer wazuh.dashboard wazuh.manager suricata suricata.eve.filter >/dev/null
sleep 8

for svc in single-node-wazuh.manager-1 single-node-wazuh.indexer-1 single-node-wazuh.dashboard-1 single-node-suricata-1 single-node-suricata.eve.filter-1; do
  state="$(docker inspect -f '{{.State.Status}}' "$svc" 2>/dev/null || true)"
  [[ "$state" == "running" ]] || fail "$svc not running (state=$state)"
done
pass "all core containers running"

docker exec single-node-wazuh.manager-1 getent hosts wazuh.indexer >/dev/null || fail "manager cannot resolve wazuh.indexer"
pass "manager can resolve indexer"

docker exec single-node-wazuh.manager-1 python3 - <<'PY' || fail "manager cannot reach wazuh.indexer:9200"
import socket
with socket.create_connection(("wazuh.indexer", 9200), timeout=5):
    pass
PY
pass "manager can reach indexer TCP/9200"

docker exec single-node-suricata.eve.filter-1 sh -lc 'test -s /var/log/suricata/eve-alert.json' || fail "eve-alert.json empty"
pass "suricata filter output exists"

TEST_IP="203.0.113.250"
TEST_TS="$(date -u +%Y-%m-%dT%H:%M:%S.000000+0000)"
PAYLOAD=$(cat <<EOF
{"timestamp":"$TEST_TS","event_type":"alert","in_iface":"enp1s0","src_ip":"$TEST_IP","srcip":"$TEST_IP","src_port":46000,"dest_ip":"192.168.0.168","dstip":"192.168.0.168","dest_port":53,"proto":"UDP","app_proto":"dns","alert_signature_id":2025451,"alert_signature":"ET INFO Monero Mining Pool DNS Lookup (xmr .pool .mingergate .com)","alert_category":"Crypto Currency Mining Activity Detected","alert_severity":2,"alert_action":"allowed","zone":"office","threat_type":"cryptomining","severity_bucket":"high","@source":"suricata"}
EOF
)

docker exec single-node-suricata.eve.filter-1 sh -lc "printf '%s\n' '$PAYLOAD' >> /var/log/suricata/eve-alert.json"
sleep 10

docker exec single-node-wazuh.manager-1 sh -lc "grep -q \"$TEST_IP\" /var/ossec/logs/alerts/alerts.log" || fail "test alert not ingested by wazuh"
pass "test alert ingested by wazuh"

docker exec single-node-wazuh.manager-1 sh -lc "grep -q \"$TEST_IP\" /var/ossec/logs/active-responses.log" || fail "active response not triggered"
pass "active response triggered"

docker exec single-node-wazuh.manager-1 sh -lc "iptables -S INPUT 2>/dev/null | grep -q \"$TEST_IP\"" || fail "iptables DROP not created"
pass "iptables DROP created"

echo "[INFO] Regression test complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
