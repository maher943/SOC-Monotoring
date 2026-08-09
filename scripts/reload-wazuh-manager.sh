#!/usr/bin/env bash
# Safely reload Wazuh manager after ConfigMap change.
#
# Problem we hit before: blindly copying /wazuh-config-mount/etc/ossec.conf
# over /var/ossec/etc/ossec.conf can replace the live cluster <key> with the
# placeholder "to_be_replaced_by_cluster_key" and break wazuh-clusterd.
#
# This script:
#   1) Backs up live ossec.conf
#   2) Merges ONLY the <integration> custom-shuffle block from the mount/snippet
#      into the live conf (or restarts STS if --restart)
#
# Usage:
#   ./reload-wazuh-manager.sh --merge-integration   # preferred, no full overwrite
#   ./reload-wazuh-manager.sh --restart              # roll STS (picks up ConfigMap mount)

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
NS="${WAZUH_NAMESPACE:-wazuh}"
POD="${WAZUH_MASTER_POD:-wazuh-manager-master-0}"
MODE="${1:-}"

if [[ "$MODE" == "--restart" ]]; then
  echo "==> Restarting StatefulSet wazuh-manager-master (ConfigMap remount)"
  kubectl -n "$NS" rollout restart sts/wazuh-manager-master
  kubectl -n "$NS" rollout status sts/wazuh-manager-master --timeout=180s
  echo "==> Re-install integration scripts (PVC may or may not retain them)"
  "$(dirname "$0")/install-integration-scripts.sh"
  exit 0
fi

if [[ "$MODE" != "--merge-integration" ]]; then
  echo "Usage: $0 --merge-integration | --restart"
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNIPPET="$ROOT/wazuh/config/integration-shuffle.snippet.xml"

echo "==> Backup live conf"
kubectl -n "$NS" exec "$POD" -- bash -lc \
  'cp -a /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak.$(date +%Y%m%d%H%M%S)'

echo "==> Merge custom-shuffle integration into live conf (preserve cluster key)"
# Push snippet + python merge into pod
kubectl -n "$NS" cp "$SNIPPET" "$NS/$POD:/tmp/integration-shuffle.snippet.xml"
kubectl -n "$NS" exec "$POD" -- python3 - <<'PY'
import re
path = "/var/ossec/etc/ossec.conf"
snippet = open("/tmp/integration-shuffle.snippet.xml").read().strip() + "\n\n"
text = open(path).read()
# strip existing custom-shuffle blocks
text = re.sub(
    r"\s*<integration>\s*<name>custom-shuffle</name>.*?</integration>\s*",
    "\n",
    text,
    flags=re.S,
)
if "  <cluster>" in text:
    text = text.replace("  <cluster>", snippet + "  <cluster>", 1)
else:
    text = text.replace("</ossec_config>", snippet + "</ossec_config>", 1)
assert text.count("custom-shuffle") == 1, text.count("custom-shuffle")
# refuse to write if cluster key looks like placeholder
m = re.search(r"<cluster>.*?<key>(.*?)</key>", text, re.S)
if m and "to_be_replaced" in m.group(1):
    raise SystemExit("REFUSING: live conf would have placeholder cluster key")
open(path, "w").write(text)
print("merged ok; custom-shuffle count=", text.count("custom-shuffle"))
if m:
    print("cluster key length=", len(m.group(1)))
PY

echo "==> Ensure scripts present"
"$(dirname "$0")/install-integration-scripts.sh"

echo "==> Reload Wazuh (manager)"
kubectl -n "$NS" exec "$POD" -- bash -lc \
  '/var/ossec/bin/wazuh-control reload || /var/ossec/bin/wazuh-control restart'

echo "==> Tail integrator / cluster briefly"
kubectl -n "$NS" exec "$POD" -- bash -lc \
  'tail -n 5 /var/ossec/logs/ossec.log; echo ---; grep -iE "cluster|integrat|custom-shuffle|ERROR" /var/ossec/logs/ossec.log | tail -n 20' \
  || true

echo "==> Done"
