#!/usr/bin/env bash
# Verify Wazuh → Shuffle → TheHive wiring without changing anything.
#
# Usage: ./verify-integration.sh

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
NS_W="${WAZUH_NAMESPACE:-wazuh}"
POD="${WAZUH_MASTER_POD:-wazuh-manager-master-0}"
HOOK_IN="http://shuffle-backend.shuffle.svc.cluster.local:5001/api/v1/hooks/webhook_bab61144-db82-4ada-aacb-62fa34893206"
HOOK_EXT="http://192.168.1.125:30080/api/v1/hooks/webhook_bab61144-db82-4ada-aacb-62fa34893206"
THEHIVE="http://192.168.1.125:30090"
SHUFFLE="http://192.168.1.125:30080"

ok() { echo "  [OK] $*"; }
bad() { echo "  [FAIL] $*"; FAIL=1; }
FAIL=0

echo "==> Cluster nodes / placement"
kubectl get pods -A -o wide \
  | awk '/wazuh-manager-master|wazuh-dashboard|wazuh-indexer|shuffle-backend|thehive-sov-7|thehive-sov-cassandra|thehive-sov-elasticsearch|thehive-sov-minio/ {print}' \
  || true

echo
echo "==> HTTP reachability"
code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$SHUFFLE/" || echo 000)
[[ "$code" =~ ^(200|301|302)$ ]] && ok "Shuffle UI $SHUFFLE ($code)" || bad "Shuffle UI $SHUFFLE ($code)"

code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$THEHIVE/index.html" || echo 000)
[[ "$code" =~ ^(200|301|302)$ ]] && ok "TheHive UI $THEHIVE ($code)" || bad "TheHive UI $THEHIVE ($code)"

echo
echo "==> Wazuh manager scripts + conf"
if kubectl -n "$NS_W" exec "$POD" -- test -x /var/ossec/integrations/custom-shuffle; then
  ok "custom-shuffle executable present"
else
  bad "custom-shuffle missing — run scripts/install-integration-scripts.sh"
fi
if kubectl -n "$NS_W" exec "$POD" -- test -f /var/ossec/integrations/custom-shuffle.py; then
  ok "custom-shuffle.py present"
else
  bad "custom-shuffle.py missing"
fi

count=$(kubectl -n "$NS_W" exec "$POD" -- grep -c 'custom-shuffle' /var/ossec/etc/ossec.conf || true)
[[ "$count" == "1" ]] && ok "exactly 1 custom-shuffle in live ossec.conf" \
  || bad "custom-shuffle count in live ossec.conf = $count (want 1)"

hook=$(kubectl -n "$NS_W" exec "$POD" -- awk '/custom-shuffle/{f=1} f&&/<hook_url>/{print; exit}' /var/ossec/etc/ossec.conf || true)
echo "  hook_url line: $hook"
echo "$hook" | grep -q 'webhook_bab61144' && ok "hook URL points at known Shuffle webhook" \
  || bad "hook URL unexpected"

echo
echo "==> ConfigMap vs live (custom-shuffle)"
cm=$(kubectl -n "$NS_W" get cm -o name | grep 'wazuh-conf-' | head -1 | sed 's|configmap/||')
cm_count=$(kubectl -n "$NS_W" get cm "$cm" -o jsonpath='{.data.master\.conf}' | grep -c custom-shuffle || true)
[[ "$cm_count" == "1" ]] && ok "ConfigMap $cm has 1 custom-shuffle" \
  || bad "ConfigMap $cm custom-shuffle count=$cm_count"

echo
echo "==> Smoke: POST sample alert to Shuffle webhook (external)"
payload='{"rule":{"id":"99999","level":10,"description":"soc-stack verify smoke","groups":["test"]},"agent":{"id":"000","name":"verify"},"id":"verify-smoke","timestamp":"2026-08-09T00:00:00.000+0000"}'
code=$(curl -s -o /tmp/shuffle-hook-resp.txt -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' \
  --connect-timeout 10 \
  -d "$payload" "$HOOK_EXT" || echo 000)
[[ "$code" =~ ^(200|201)$ ]] && ok "Shuffle webhook accepted smoke ($code)" \
  || bad "Shuffle webhook smoke failed ($code) body=$(head -c 200 /tmp/shuffle-hook-resp.txt 2>/dev/null)"

echo
echo "==> In-cluster DNS (from Wazuh master)"
kubectl -n "$NS_W" exec "$POD" -- bash -lc \
  "python3 - <<'PY'
import socket
for h in ['shuffle-backend.shuffle.svc.cluster.local','thehive-sov.default.svc.cluster.local']:
  try:
    print(h, '->', socket.gethostbyname(h))
  except Exception as e:
    print(h, 'FAIL', e)
PY" 2>&1 | sed 's/^/  /'

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "RESULT: all checks passed"
  exit 0
else
  echo "RESULT: some checks failed — see above"
  exit 1
fi
