# Progress log

Each meaningful integration step is recorded here and pushed to GitHub.

## 2026-08-09 — UI walkthrough (how to *see* the integration)

### Problem
Dashboards looked “unchanged” because there is no new Wazuh/Shuffle widget — only cases and workflow executions.

### What we did
1. Documented exact URLs, orgs, and screens in [UI-WALKTHROUGH.md](UI-WALKTHROUGH.md).
2. Verified lab state via API:
   - TheHive org **SOC**: cases present (e.g. `#19` …).
   - Shuffle workflow **Wazuh Alerts**: FINISHED executions linked to those cases.
3. Ran a walkthrough alert through integrator → Shuffle → TheHive → newest case **#21**  
   `Wazuh [10] sshd: attempt to login using a non-existent user`.

### How you view it
| UI | URL | What to open |
|----|-----|----------------|
| TheHive | http://192.168.1.125:30090 | Org **SOC** → Cases → `#21` (and older `Wazuh […]` titles) |
| Shuffle | http://192.168.1.125:30080 | Workflow **Wazuh Alerts** → Executions |
| Wazuh | https://192.168.1.125:31294 | No new menu; integration is manager-side only |

---

## 2026-08-09 — Case titles + ConfigMap persistence

### Problem
TheHive cases were created as `Wazuh []` (empty title/fields). Shuffle only expands **`$exec`** (the whole webhook body as a JSON *string*). Nested paths (`$rule.level`, `$exec.rule.level`) do **not** expand.

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
