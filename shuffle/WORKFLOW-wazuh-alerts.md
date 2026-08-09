# Shuffle workflow — Wazuh Alerts

| Field | Value |
|-------|--------|
| Name | Wazuh Alerts |
| Workflow UUID | `7c3ff717-660d-49a5-8751-b6b06f25cb1b` |
| Webhook UUID | `bab61144-db82-4ada-aacb-62fa34893206` |
| Trigger | Webhook |
| Action | HTTP POST → TheHive `/api/v1/case` |
| HTTP body | **`$exec`** (entire webhook JSON = TheHive case object) |
| TheHive org header | `X-Organisation: SOC` |
| Auth | API key for `shuffle@soc.local` (local `CREDENTIALS.txt` only) |

## Why body is `$exec`

Shuffle does not expand nested Wazuh fields. The Wazuh integrator
(`wazuh/scripts/custom-shuffle.py`) pre-builds the TheHive case JSON;
Shuffle only forwards it.

## URLs

```text
# From Wazuh manager (preferred)
http://shuffle-backend.shuffle.svc.cluster.local:5001/api/v1/hooks/webhook_bab61144-db82-4ada-aacb-62fa34893206

# LAN smoke test
http://192.168.1.125:30080/api/v1/hooks/webhook_bab61144-db82-4ada-aacb-62fa34893206
```

## Export in this repo

Redacted workflow dump (no live API keys / images trimmed):

`shuffle/workflows/wazuh-alerts.redacted.json`
