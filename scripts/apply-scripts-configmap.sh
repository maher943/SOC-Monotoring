#!/usr/bin/env bash
# Build ConfigMap wazuh-custom-shuffle from wazuh/scripts/* and apply it.
# Then copy those files onto the manager PVC (source of truth remains Git).
#
# Usage:
#   ./apply-scripts-configmap.sh           # apply CM + install onto pod
#   ./apply-scripts-configmap.sh --cm-only # ConfigMap only

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS="${WAZUH_NAMESPACE:-wazuh}"
CM_ONLY=0
[[ "${1:-}" == "--cm-only" ]] && CM_ONLY=1

WRAPPER="$ROOT/wazuh/scripts/custom-shuffle"
PY="$ROOT/wazuh/scripts/custom-shuffle.py"
[[ -f "$WRAPPER" && -f "$PY" ]] || { echo "missing scripts under wazuh/scripts/"; exit 1; }

echo "==> Applying ConfigMap wazuh-custom-shuffle from Git files"
kubectl -n "$NS" create configmap wazuh-custom-shuffle \
  --from-file=custom-shuffle="$WRAPPER" \
  --from-file=custom-shuffle.py="$PY" \
  --dry-run=client -o yaml \
  | sed '/^metadata:/a\  labels:\n    app.kubernetes.io/name: wazuh\n    soc-stack.integrations: shuffle' \
  | kubectl apply -f -

mkdir -p "$ROOT/wazuh/manifests"
kubectl -n "$NS" get configmap wazuh-custom-shuffle -o yaml \
  | grep -Ev '^\s*(resourceVersion|uid|creationTimestamp|managedFields):' \
  > "$ROOT/wazuh/manifests/custom-shuffle-configmap.generated.yaml" || true

if [[ "$CM_ONLY" -eq 1 ]]; then
  echo "==> ConfigMap only — done"
  exit 0
fi

echo "==> Installing onto manager pod"
"$ROOT/scripts/install-integration-scripts.sh"
