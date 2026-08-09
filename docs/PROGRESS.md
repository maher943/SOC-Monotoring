# Progress log

Each meaningful integration step is recorded here and pushed to GitHub.

## 2026-08-09 — Case titles + ConfigMap persistence

### Problem
TheHive cases were created as `Wazuh []` (empty title/fields). Shuffle only expands **`$exec`** (the whole webhook body as a JSON *string*). Nested paths (`$rule.level`, `$exec.rule.level`) and sibling keys (`$rule_level`) do **not** expand.

### Fix
1. **`wazuh/scripts/custom-shuffle.py`** builds a **TheHive `/api/v1/case` JSON** (title, description, severity, tags).
2. Shuffle workflow HTTP action **body = `$exec`** (forward unchanged to TheHive).
3. Integrator scripts are versioned in Git and applied as ConfigMap **`wazuh-custom-shuffle`** via `scripts/apply-scripts-configmap.sh`, then copied onto the manager PVC.

### Verified
- Integrator smoke → TheHive case **#19**:  
  `Wazuh [10] sshd: brute force trying to get access to the system.`

### Files touched
- `wazuh/scripts/custom-shuffle.py`
- `scripts/apply-scripts-configmap.sh`
- `wazuh/manifests/README.md`
- `shuffle/workflows/wazuh-alerts.redacted.json` (exported, API key redacted)
- `shuffle/WORKFLOW-wazuh-alerts.md`
- `docs/ARCHITECTURE.md`

---

## Earlier (same day) — Repo bootstrap

- Created public repo layout under `/home/maher/SOC-Monotoring`
- Architecture + runbook scripts (patch ConfigMap, safe reload, cluster-key fix, verify)
- Pushed to https://github.com/maher943/SOC-Monotoring
