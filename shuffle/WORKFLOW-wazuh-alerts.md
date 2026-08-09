# Shuffle workflow — Wazuh Alerts

Tracked metadata for the workflow that receives Wazuh integrator POSTs and opens TheHive cases.

| Field | Value |
|-------|--------|
| Name | Wazuh Alerts |
| Workflow UUID | `7c3ff717-660d-49a5-8751-b6b06f25cb1b` |
| Webhook UUID | `bab61144-db82-4ada-aacb-62fa34893206` |
| Trigger | Webhook (JSON body = full Wazuh alert) |
| Action | HTTP POST → TheHive `/api/v1/case` |
| TheHive org header | `X-Organisation: SOC` |
| Auth | API key for `shuffle@soc.local` (see `../CREDENTIALS.txt`) |

## URLs

```text
# From Wazuh manager (preferred)
http://shuffle-backend.shuffle.svc.cluster.local:5001/api/v1/hooks/webhook_bab61144-db82-4ada-aacb-62fa34893206

# From laptop / LAN smoke test
http://192.168.1.125:30080/api/v1/hooks/webhook_bab61144-db82-4ada-aacb-62fa34893206
```

## Notes

- Shuffle workflow branches must be stored as a **JSON array** of edge objects (a map caused PUT 400 when editing via API).
- Prefer editing the workflow in the Shuffle UI; when stable, export JSON here for Git history.
- Wazuh snippet that points at this webhook: `../wazuh/config/integration-shuffle.snippet.xml`
