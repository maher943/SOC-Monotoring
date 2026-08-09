# Architecture — Wazuh, TheHive, Shuffle

Lab SOC on a **k3s** cluster. Nodes talk over **OpenVPN** (`10.8.0.0/24`); Flannel uses those IPs, so **cross-node pod traffic hairpins through the VPN hub** and can add hundreds of ms of latency. That is why each heavy stack is **colocated on one node**.

**Today's date context:** 2026-08-09. This doc describes what is installed and the plan for them to work together.

---

## 1. Cluster map

| Node | INTERNAL-IP (VPN) | Role | Main workloads |
|------|-------------------|------|----------------|
| `soc-vm` | 10.8.0.1 | VPN hub + worker | **TheHive** (+ Cassandra, Elasticsearch, MinIO) |
| `master-node` | 10.8.0.2 | control-plane (LAN often `192.168.1.125`) | k3s API; light pods |
| `worker` | 10.8.0.3 | worker | **Wazuh manager master** |
| `node1` | 10.8.0.4 | worker | **Shuffle** (full stack) |
| `nodemanager` | 10.8.0.5 | worker | **Wazuh indexer + dashboard** |

LAN access for UIs/NodePorts is typically via **`192.168.1.125`** (master). The same NodePorts also work on any node IP (`10.8.0.x` or LAN) because kube-proxy publishes them cluster-wide.

```
                    ┌─────────────────────────────────────────┐
                    │              k3s (Flannel/VPN)          │
  Agents/events ──► │  Wazuh (worker / nodemanager)           │
                    │         │ alerts level ≥ 7              │
                    │         ▼                               │
                    │  custom-shuffle integrator              │
                    │         │ HTTP POST JSON                │
                    │         ▼                               │
                    │  Shuffle webhook (node1)                │
                    │         │ HTTP POST /api/v1/case        │
                    │         ▼                               │
                    │  TheHive org SOC (soc-vm)               │
                    └─────────────────────────────────────────┘
```

---

## 2. How each product was installed

### 2.1 Wazuh

- **Method:** official **wazuh-kubernetes** kustomize tree  
  Source: `upstream `wazuh-kubernetes` checkout (not vendored here)`  
  Namespace: `wazuh` (created ~64 days ago)
- **Not** Helm. Manifests under `wazuh-kubernetes/wazuh` + env overlays.
- **Config:** ConfigMap `wazuh-conf-m5756d8fbh` keys `master.conf` / worker conf.  
  Tracked export: `wazuh/config/master.conf.current`
- **Services (NodePorts / LB):**
  - Manager API: `55000` → NodePort **32090**
  - Agent events (workers): **30900**
  - Dashboard HTTPS: **31294**
  - Indexer: **30937**
- **Secrets:** e.g. `wazuh-api-cred` (`wazuh-wui` / see CREDENTIALS.txt)

### 2.2 TheHive

- **Method:** StrangeBee Helm chart **thehive-1.0.5** (app **5.7.5-1**)  
  Release: `thehive-sov` in namespace `default`  
  Values: `thehive/values.yaml` in this repo (secrets are placeholders — use local values / cluster secrets)
- **Why pinned to `soc-vm`:** JanusGraph / Cassandra ID allocation fails when RTT across VPN exceeds ~300 ms. Entire stack (app + Cassandra + ES + MinIO) must stay on one node.
- **UI:** ClusterIP `thehive-sov:9000` + NodePort service **`thehive-sov-nodeport` :30090**  
  Manifest: `thehive/nodeport.yaml`
- **Orgs / users:**
  - Platform admin org: `admin@thehive.local` (password in local `CREDENTIALS.txt`; cannot create cases for ops)
  - Ops org **SOC**, automation user `shuffle@soc.local` + API key (local `CREDENTIALS.txt`)
  - API calls need header **`X-Organisation: SOC`**

### 2.3 Shuffle

- **Method:** Official Shuffle Helm chart from an upstream Shuffle git checkout  
  Chart path in upstream: `functions/kubernetes/charts/shuffle`  
  Values used for install: `shuffle/values.yaml` in this repo  
  Release: `shuffle` in namespace **`shuffle`** (namespace already existed; Helm installed *into* it)
- **Why pinned to `node1`:** 8 CPU, more free disk than `worker` (which already runs Wazuh master). Same colocation rule as TheHive.
- **UI:** NodePort **30080** (`shuffle-frontend-nodeport`)  
  `baseUrl`: `http://192.168.1.125:30080` (LAN). VPN alternative: `http://10.8.0.2:30080`.
- **Ingress:** disabled (chart helper bug with bundled common chart).
- **Workers:** managed via Helm (`manageWorkerDeployments: false` pattern in values — Orborus + worker deploy).
- **Creds:** local `CREDENTIALS.txt` (gitignored; see `CREDENTIALS.example.txt`) + secret `shuffle-backend-env`

---

## 3. How they work together (plan + current wiring)

### Goal

1. Wazuh raises an alert (rule level ≥ **7**).  
2. Manager **integrator** runs `custom-shuffle` / `custom-shuffle.py`.  
3. Script builds a **TheHive case JSON** (title/description/severity/tags) and POSTs it to the **Shuffle webhook**.  
4. Shuffle workflow **Wazuh Alerts** forwards the body as **`$exec`** to TheHive `POST /api/v1/case`.  
5. Analysts work the case in TheHive (org SOC); later enrich with Shuffle apps / Wazuh API as needed.

> **Shuffle variable caveat:** only `$exec` (whole webhook body string) substitutes reliably. Nested paths like `$rule.level` stay empty — that is why the integrator pre-builds the case.

### Current Shuffle workflow

| Field | Value |
|-------|--------|
| Name | Wazuh Alerts |
| Workflow id | `7c3ff717-660d-49a5-8751-b6b06f25cb1b` |
| Webhook id | `bab61144-db82-4ada-aacb-62fa34893206` |
| Steps | Webhook trigger → HTTP → TheHive `POST /api/v1/case` |

**In-cluster webhook URL (used by Wazuh):**

```text
http://shuffle-backend.shuffle.svc.cluster.local:5001/api/v1/hooks/webhook_bab61144-db82-4ada-aacb-62fa34893206
```

**External test URL:**

```text
http://192.168.1.125:30080/api/v1/hooks/webhook_bab61144-db82-4ada-aacb-62fa34893206
```

TheHive auth on the HTTP action: Bearer / API key for `shuffle@soc.local`, header `X-Organisation: SOC`, body built from `$rule.*` / agent fields in the Wazuh JSON.

### Wazuh side (file-based, not one-off exec)

| Artifact | Location |
|----------|----------|
| Shell wrapper | `wazuh/scripts/custom-shuffle` |
| Python sender (builds TheHive case JSON) | `wazuh/scripts/custom-shuffle.py` |
| Conf snippet | `wazuh/config/integration-shuffle.snippet.xml` |
| Scripts ConfigMap apply | `scripts/apply-scripts-configmap.sh` → CM `wazuh-custom-shuffle` |
| Install scripts onto PVC | `scripts/install-integration-scripts.sh` |
| Patch ConfigMap idempotently | `scripts/patch-wazuh-configmap.sh` |
| Safe live merge / reload | `scripts/reload-wazuh-manager.sh` |
| Verify | `scripts/verify-integration.sh` |
| Redacted workflow export | `shuffle/workflows/wazuh-alerts.redacted.json` |

Wazuh requires integrator names prefixed with **`custom-`**. Scripts must live under `/var/ossec/integrations/` on the **manager master** with mode `750`, owner `root:wazuh`.

**Important lesson (traceability):**  
Do **not** blindly `cp` the ConfigMap mount over `/var/ossec/etc/ossec.conf`. Both the mount and (after a bad copy) the live conf can contain placeholder cluster key `to_be_replaced_by_cluster_key`. The real 32-char key lives in secret `wazuh-cluster-key`. Overwriting/leaving the placeholder breaks `wazuh-clusterd`.  

- Prefer `--merge-integration` for the Shuffle block only.  
- If the key is wrong: `./scripts/fix-wazuh-cluster-key.sh --apply`

Scripts on the PVC can disappear after some STS recreations depending on volume layout — always re-run `install-integration-scripts.sh` after a restart if verify fails.

---

## 4. Network / URL cheat sheet

| Service | LAN | VPN (example) | In-cluster |
|---------|-----|---------------|------------|
| Shuffle UI | http://192.168.1.125:30080 | http://10.8.0.2:30080 | http://shuffle-frontend.shuffle.svc |
| Shuffle API/hooks | same host :30080 | same | http://shuffle-backend.shuffle.svc:5001 |
| TheHive UI | http://192.168.1.125:30090 | http://10.8.0.2:30090 | http://thehive-sov.default.svc:9000 |
| Wazuh API | https://192.168.1.125:32090 | https://10.8.0.2:32090 | https://wazuh.wazuh.svc:55000 |
| Wazuh Dashboard | https://192.168.1.125:31294 | https://10.8.0.x:31294 | (dashboard service) |

Kubeconfig for user `maher`: `~/.kube/config` (copy of `/etc/rancher/k3s/k3s.yaml`). Do not use an old minikube config pointing at `192.168.49.2`.

---

## 5. Apply / change order (runbook)

1. Confirm pods healthy:  
   `kubectl get pods -n wazuh -o wide`  
   `kubectl get pods -n shuffle -o wide`  
   `kubectl get pods -n default -o wide | grep thehive`
2. Install integrator files from git/dir:  
   `./scripts/install-integration-scripts.sh`
3. Dry-run ConfigMap patch, review `/tmp/wazuh-master.conf.patched`, then:  
   `./scripts/patch-wazuh-configmap.sh --apply`
4. Merge into live conf + reload:  
   `./scripts/reload-wazuh-manager.sh --merge-integration`
5. Verify:  
   `./scripts/verify-integration.sh`
6. Optional: raise a real high-level alert on an agent and confirm a new case in TheHive (org SOC).

To change the threshold or webhook: edit `wazuh/config/integration-shuffle.snippet.xml`, then re-run steps 3–5.

To change TheHive case mapping: edit the Shuffle workflow in the UI (workflow id above); keep this doc’s webhook id in sync if the trigger is recreated.

---

## 6. Future / next integration steps

- Tune `level` / `rule_id` / `group` filters so only actionable alerts become cases.
- Add Shuffle branches: enrich from Wazuh API, attach observables, optional auto-close for noise.
- Optionally set Shuffle `baseUrl` to a VPN IP if operators always access via OpenVPN.
- Mount ConfigMap `wazuh-custom-shuffle` into the manager STS (subPath) so a PVC wipe cannot drop scripts without re-apply.
- See also [PROGRESS.md](PROGRESS.md) for completed steps.

---

## 7. Related paths (on the lab host)

| What | Path |
|------|------|
| This repo (canonical docs/scripts) | `/home/maher/SOC-Monotoring` |
| Live secrets (not in git) | `/home/maher/soc-stack/CREDENTIALS.txt`, `/home/maher/shuffle/CREDENTIALS.txt` |
| Shuffle Helm chart copy used to install | `/home/maher/shuffle/chart` |
| Shuffle upstream git | `/home/maher/shuffle-src` |
| TheHive live Helm values | `/home/maher/thehive/values.yaml` |
| Wazuh kustomize checkout | `/home/maher/wazuh-kubernetes` |

---

## 8. Design constraints (do not forget)

1. **Colocate** each stateful stack on one node (VPN latency).  
2. **Never** recreate namespaces that already exist (`shuffle`, `wazuh`) for “clean install” without an explicit decision.  
3. Prefer **scripts + ConfigMaps + files** in this repo for any conf change.  
4. Preserve Wazuh **cluster key** when touching `ossec.conf`.  
5. TheHive case creation must use org **SOC**, not the platform admin org.
