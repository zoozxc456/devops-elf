# Odoo Plugin

**English** | [繁體中文](README.zh-TW.md)

Provides multiline traceback merging, level/db/logger parsing, and a dedicated dashboard for native Odoo logs. The db/logger fields use Loki structured metadata; the core normalizes levels to TRACE / DEBUG / INFO / WARN / ERROR / CRITICAL.

## Enable

```bash
# Run from lookout/; include any other plugins you want to keep.
python3 scripts/plugins.py apply odoo
```

Recreate Alloy, Loki, and Grafana as described in the [plugin guide](../README.md). For Ansible, set `lookout_plugins: [odoo]`. Enable the plugin on the Server and Agents that parse Odoo logs.

Add labels to your Odoo Compose service; service and container names are customizable:

```yaml
services:
  odoo:
    labels:
      lookout.enable: "true"
      lookout.env: prod
      lookout.service: odoo
      lookout.format: odoo
```

Recreate the Odoo container to apply labels. `LOOKOUT_ENVS` must allow the corresponding environment. Use Odoo's default text log format:

```text
2026-10-23 05:12:33,123 7 ERROR mydb odoo.http: message
```

For applications emitting JSON, use the core `lookout.format=json` parser. Odoo-specific fields and dashboards may need adjustments for that format.

## Queries and alerts

An Odoo log overview dashboard is added to Grafana's Lookout folder, with env / host / service / db filters.

```logql
{format="odoo", env="prod"}
{format="odoo", level=~"ERROR|CRITICAL"} | db="mydb"
```

Error bursts use the core `AppErrorLogBurst` alert without duplicate rules. PostgreSQL metrics and logs for Odoo use the core PostgreSQL support. Enable them separately through the [target configuration guide](../../docs/targets.md); fixed database container names are unnecessary.
