#!/usr/bin/env bash
# Restore Wazuh <cluster><key> from secret wazuh-cluster-key into:
#   1) live /var/ossec/etc/ossec.conf on the master
#   2) ConfigMap master.conf (so future mounts are not wrong)
#
# Why: a blind copy from the ConfigMap mount previously left
#   to_be_replaced_by_cluster_key
# which breaks wazuh-clusterd (key must be 32 alphanumeric chars).
#
# Usage:
#   ./fix-wazuh-cluster-key.sh           # dry-run (print lengths only)
#   ./fix-wazuh-cluster-key.sh --apply

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
NS="${WAZUH_NAMESPACE:-wazuh}"
POD="${WAZUH_MASTER_POD:-wazuh-manager-master-0}"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

KEY="$(kubectl -n "$NS" get secret wazuh-cluster-key -o jsonpath='{.data.key}' | base64 -d)"
[[ ${#KEY} -eq 32 ]] || { echo "secret key length ${#KEY} != 32"; exit 1; }
echo "==> secret wazuh-cluster-key length=${#KEY}"

CM="$(kubectl -n "$NS" get cm -o name | grep 'wazuh-conf-' | head -1 | sed 's|configmap/||')"
echo "==> ConfigMap: $CM"

python3 - "$NS" "$CM" "$POD" "$KEY" "$APPLY" <<'PY'
import json, re, subprocess, sys
ns, cm, pod, key, apply = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] == "1"

def replace_key(text, key):
    new, n = re.subn(
        r"(<cluster>[\s\S]*?<key>)(.*?)(</key>)",
        lambda m: m.group(1) + key + m.group(3),
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit(f"expected 1 <cluster><key> replacement, got {n}")
    return new

# --- ConfigMap ---
cm_obj = json.loads(subprocess.check_output(["kubectl", "-n", ns, "get", "cm", cm, "-o", "json"]))
master = cm_obj["data"]["master.conf"]
old = re.search(r"<cluster>[\s\S]*?<key>(.*?)</key>", master).group(1)
print(f"==> CM key before: {old!r} (len={len(old)})")
master2 = replace_key(master, key)
cm_obj["data"]["master.conf"] = master2
# worker conf if present
if "worker.conf" in cm_obj["data"] or any(k.endswith(".conf") for k in cm_obj["data"]):
    for k, v in list(cm_obj["data"].items()):
        if k == "master.conf":
            continue
        if "<cluster>" in v and "<key>" in v:
            before = re.search(r"<key>(.*?)</key>", v)
            print(f"==> {k} key before: {before.group(1)!r}" if before else f"==> {k}: no key")
            cm_obj["data"][k] = replace_key(v, key)

path = "/tmp/wazuh-conf-keyfixed.json"
open(path, "w").write(json.dumps({"apiVersion":"v1","kind":"ConfigMap","metadata":{"name":cm,"namespace":ns},"data":cm_obj["data"]}, indent=2))
open("/tmp/wazuh-master.conf.keyfixed", "w").write(master2)
print(f"==> wrote {path}")

# --- live conf ---
live = subprocess.check_output(["kubectl", "-n", ns, "exec", pod, "--", "cat", "/var/ossec/etc/ossec.conf"], text=True)
old_live = re.search(r"<cluster>[\s\S]*?<key>(.*?)</key>", live).group(1)
print(f"==> live key before: {old_live!r} (len={len(old_live)})")
live2 = replace_key(live, key)

if not apply:
    print("==> Dry-run only. Re-run with --apply")
    sys.exit(0)

subprocess.check_call(["kubectl", "apply", "-f", path])
# backup + write live via stdin
subprocess.run(
    ["kubectl", "-n", ns, "exec", "-i", pod, "--", "bash", "-lc",
     "cp -a /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak.keyfix.$(date +%s) && cat > /var/ossec/etc/ossec.conf"],
    input=live2.encode(),
    check=True,
)
print("==> Applied CM + live conf. Reloading manager...")
subprocess.check_call(["kubectl", "-n", ns, "exec", pod, "--", "bash", "-lc",
                       "/var/ossec/bin/wazuh-control reload || /var/ossec/bin/wazuh-control restart"])
print("==> Done. Check: kubectl -n wazuh exec wazuh-manager-master-0 -- /var/ossec/bin/cluster_control -l")
PY
