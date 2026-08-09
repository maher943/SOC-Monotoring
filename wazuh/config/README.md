# Export of ConfigMap wazuh-conf-*/master.conf for review/diff.

Cluster `<key>` is **REDACTED** in `master.conf.current` — the real value is in secret `wazuh/wazuh-cluster-key`.

Do not paste a live key into this file. Use `scripts/fix-wazuh-cluster-key.sh` to sync the secret into the live conf + ConfigMap.

Refresh (redacted):

```bash
kubectl -n wazuh get cm wazuh-conf-m5756d8fbh -o jsonpath='{.data.master\.conf}' \
  | sed 's#<key>.*</key>#<key>REDACTED_SEE_SECRET_wazuh-cluster-key</key>#' \
  > wazuh/config/master.conf.current
```
