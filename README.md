# SOC-Monotoring

Lab SOC stack documentation and **file-based** integration for **Wazuh → Shuffle → TheHive** on k3s.

Public repo: https://github.com/maher943/SOC-Monotoring

## What's in this repo

| Path | Purpose |
|------|---------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How each product is installed, node placement, networking, integration plan |
| [CREDENTIALS.example.txt](CREDENTIALS.example.txt) | Template for local secrets (copy to `CREDENTIALS.txt`, never commit) |
| `wazuh/` | Integrator scripts + ConfigMap snippet |
| `thehive/` | Helm values (secrets redacted) + NodePort manifest |
| `shuffle/` | Helm values + workflow metadata |
| `scripts/` | Apply / reload / verify helpers |

Upstream charts/repos are **not** fully vendored here (keep them separate):

- Shuffle chart: official Shuffle git → `functions/kubernetes/charts/shuffle`
- TheHive chart: StrangeBee Helm chart
- Wazuh: official [wazuh-kubernetes](https://github.com/wazuh/wazuh-kubernetes) kustomize

## Quick verify (on the cluster host)

```bash
cp CREDENTIALS.example.txt CREDENTIALS.txt   # fill locally
./scripts/verify-integration.sh
```

## Apply Wazuh → Shuffle link

```bash
./scripts/install-integration-scripts.sh
./scripts/patch-wazuh-configmap.sh            # dry-run
./scripts/patch-wazuh-configmap.sh --apply
./scripts/reload-wazuh-manager.sh --merge-integration
./scripts/verify-integration.sh
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full picture.
