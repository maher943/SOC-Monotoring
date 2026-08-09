# Wazuh → Shuffle integrator files

| File | Role |
|------|------|
| `../scripts/custom-shuffle` | Shell wrapper (name must start with `custom-`) |
| `../scripts/custom-shuffle.py` | Builds TheHive case JSON and POSTs to Shuffle webhook |
| `custom-shuffle-configmap.generated.yaml` | Rendered after `apply-scripts-configmap.sh` |

Apply:

```bash
./scripts/apply-scripts-configmap.sh
```

Shuffle HTTP body must be `$exec` (see `docs/PROGRESS.md`).
