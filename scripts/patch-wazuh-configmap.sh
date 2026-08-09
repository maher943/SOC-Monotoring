#!/usr/bin/env bash
# Patch the Wazuh manager ConfigMap (master.conf) to include the Shuffle
# <integration> block — exactly once. Does NOT overwrite the whole conf blindly.
#
# Usage:
#   ./patch-wazuh-configmap.sh           # dry-run (writes /tmp, shows diff summary)
#   ./patch-wazuh-configmap.sh --apply   # apply ConfigMap (you still reload/restart)
#
# After apply, either:
#   - restart the manager STS, OR
#   - copy mount -> live conf carefully (preserve runtime cluster key) + reload
#
# See docs/ARCHITECTURE.md section "Apply the Wazuh → Shuffle link".

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS="${WAZUH_NAMESPACE:-wazuh}"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

SNIPPET_FILE="$ROOT/wazuh/config/integration-shuffle.snippet.xml"
[[ -f "$SNIPPET_FILE" ]] || { echo "missing $SNIPPET_FILE"; exit 1; }

CM_NAME="$(kubectl -n "$NS" get cm -o name | grep 'wazuh-conf-' | head -1 | sed 's|configmap/||')"
[[ -n "$CM_NAME" ]] || { echo "No wazuh-conf-* ConfigMap in $NS"; exit 1; }
echo "==> Using ConfigMap: $CM_NAME"

python3 - "$CM_NAME" "$NS" "$SNIPPET_FILE" "$APPLY" <<'PY'
import json, re, subprocess, sys

cm_name, ns, snippet_path, apply = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
snippet = open(snippet_path).read().strip() + "\n\n"

cm = json.loads(subprocess.check_output(
    ["kubectl", "-n", ns, "get", "cm", cm_name, "-o", "json"]
))
master = cm["data"]["master.conf"]
before = master.count("custom-shuffle")

# Remove ANY existing custom-shuffle integration blocks (idempotent)
master = re.sub(
    r"\s*<!--\s*Shuffle SOAR webhook:.*?-->\s*",
    "\n",
    master,
    flags=re.S,
)
master = re.sub(
    r"\s*<integration>\s*<name>custom-shuffle</name>.*?</integration>\s*",
    "\n",
    master,
    flags=re.S,
)

if "  <cluster>" in master:
    master = master.replace("  <cluster>", snippet + "  <cluster>", 1)
else:
    master = master.replace("</ossec_config>", snippet + "</ossec_config>", 1)

after = master.count("custom-shuffle")
print(f"==> custom-shuffle references: before={before} after={after}")
if after != 1:
    raise SystemExit(f"Expected exactly 1 custom-shuffle reference, got {after}")

out = {
    "apiVersion": "v1",
    "kind": "ConfigMap",
    "metadata": {"name": cm_name, "namespace": ns},
    "data": dict(cm["data"]),
}
out["data"]["master.conf"] = master
path = "/tmp/wazuh-conf-patched.json"
open(path, "w").write(json.dumps(out, indent=2))
# Also drop a readable conf copy for review
open("/tmp/wazuh-master.conf.patched", "w").write(master)
print(f"==> Wrote {path}")
print("==> Wrote /tmp/wazuh-master.conf.patched (review me)")

if apply:
    subprocess.check_call(["kubectl", "apply", "-f", path])
    print("==> Applied ConfigMap. Restart/reload manager to take effect.")
else:
    print("==> Dry-run only. Re-run with --apply to push the ConfigMap.")
PY

chmod +x "$0" 2>/dev/null || true
