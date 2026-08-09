#!/usr/bin/env bash
# Install custom-shuffle scripts into the Wazuh manager pod (PVC path).
# Traceable alternative to one-off `kubectl exec ... cat > file`.
#
# Usage:
#   ./install-integration-scripts.sh
#
# Requires: kubectl, KUBECONFIG pointing at the k3s cluster.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS="${WAZUH_NAMESPACE:-wazuh}"
POD="${WAZUH_MASTER_POD:-wazuh-manager-master-0}"
DEST="/var/ossec/integrations"

echo "==> Copying scripts to ${NS}/${POD}:${DEST}"
kubectl -n "$NS" exec "$POD" -- mkdir -p "$DEST"
kubectl -n "$NS" cp "$ROOT/wazuh/scripts/custom-shuffle" "$NS/$POD:$DEST/custom-shuffle"
kubectl -n "$NS" cp "$ROOT/wazuh/scripts/custom-shuffle.py" "$NS/$POD:$DEST/custom-shuffle.py"
kubectl -n "$NS" exec "$POD" -- bash -lc "
  chmod 750 $DEST/custom-shuffle $DEST/custom-shuffle.py
  chown root:wazuh $DEST/custom-shuffle $DEST/custom-shuffle.py
  ls -la $DEST/custom-shuffle $DEST/custom-shuffle.py
"
echo "==> Done. Scripts are on the manager PVC (survive pod restarts if PVC persists)."
