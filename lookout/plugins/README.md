# Lookout Plugins

**English** | [繁體中文](README.zh-TW.md)

The core provides host/container monitoring, generic logs (raw / JSON / logfmt / PostgreSQL), database exporters, and general alerts. Odoo- and Nginx-specific parsers, dashboards, and rules live here and are disabled by default.

| Plugin | Contents |
|---|---|
| [odoo](odoo/README.md) | Multiline tracebacks, db/logger metadata, and an Odoo dashboard |
| [nginx](nginx/README.md) | Access/error log parsing, Nginx configuration examples, a dashboard, and 5xx/latency alerts |

## Manual deployment

Run from the Lookout root. Python 3 is required; no additional packages are needed:

```bash
python3 scripts/plugins.py list
python3 scripts/plugins.py apply odoo nginx  # Enable both.
# python3 scripts/plugins.py apply nginx    # Nginx only.
# python3 scripts/plugins.py apply          # Core only.
```

Arguments after `apply` are the **complete plugin list**, not incremental additions. The command generates `agent/generated/` and `server/generated/` without modifying source configuration, .env files, data, or secrets. Generated directories are tool-managed and excluded from Git; do not edit them directly. Running the command again rebuilds output from current sources and removes artifacts for disabled plugins. Invalid or duplicate names, filename conflicts, and dashboard UID conflicts are rejected.

Each deployment host needs its own artifacts: generate the required parsers on Agent hosts, and enable plugins for the dashboards and alerts needed on Server hosts. You can generate output on a control host with `--output /tmp/lookout-build`, then copy `agent/generated/` and `server/generated/` to the corresponding deployment directories. Remote hosts do not need the full source tree.

Run `apply` once before the first startup, even if no plugins are needed. After changing the plugin list or source configuration, run it again and apply the changes:

```bash
cd agent
docker compose up -d --force-recreate alloy
# On the Server host, from its server/ directory:
docker compose up -d --force-recreate loki grafana
```

Generated configuration is loaded through bind mounts. Recreate containers after updates to load the new content. Plugins do not modify application containers; add labels and configure log formats as described in each plugin's guide. Logs using a disabled plugin's format are dropped to avoid implying that parsing is active.

## Ansible

Set the following in group_vars or per-host host_vars:

```yaml
lookout_plugins: [odoo, nginx]
```

The default is `[]`. Roles generate each host's configuration on the control host and synchronize it remotely; manual `apply` is unnecessary. Agent pipeline changes recreate Alloy. Server rule/dashboard synchronization removes disabled plugins, and Loki/Grafana reload those files automatically. Services are recreated on the initial mount-path transition when Compose changes.

## Structure and extensions

```text
plugins/<name>/
  README.md
  README.zh-TW.md
  agent/log-stages.alloy.inc   # Stages inserted into loki.process, not standalone config
  grafana/dashboards/*.json    # Optional; unique filenames and UIDs required
  loki/rules/fake/*.yml        # Optional; single-tenant alert rules
  config/                     # Optional; application configuration examples
```

Plugin names use lowercase letters, digits, and hyphens; the format label must match the name. Scope stages to the plugin's format with `stage.match`. The core normalizes extracted levels and reapplies `LOOKOUT_ENVS` filtering. Store high-cardinality fields such as db, logger, and vhost in structured metadata.

All stages are combined into one `loki.process` so extracted fields remain available for shared level normalization. Do not load snippets as standalone Alloy components. Plugins currently supply log stages, Loki rules, and Grafana dashboards; database exporters continue to use the core targets mechanism.

## Validation

Run from the Lookout root:

```bash
./scripts/check.sh             # Core only.
./scripts/check.sh odoo nginx  # Core and both plugins.
python3 -m unittest discover -s tests -p 'test_plugins.py'
```
