# Lookout

**English** | [繁體中文](README.zh-TW.md)

[Current version](VERSION) · [Changelog](CHANGELOG.md) · [Versioning](docs/versioning.md) · [Contributing](../CONTRIBUTING.md) · [Security](../SECURITY.md) · [MIT License](../LICENSE)

A self-hosted Linux Docker monitoring stack built with **Grafana + Loki + Alloy + Prometheus**, with Alertmanager for notifications. Grafana Alloy collects metrics and logs from hosts, containers, applications, and databases. Deploy on your own hardware, cloud VMs, or VPN networks with your own container names and cloud accounts.

```text
Docker hosts (one or more)                  Monitoring host
Alloy ── logs push ───────────────────────→ Loki ─────────┐
  ├ Host / cAdvisor                                      ├→ Alertmanager → Notifications
  ├ Container stdout / stderr              Prometheus ───┘
  └ Optional DB exporters ── remote_write ─→    ↑
                                            Grafana queries both
```

## Quick start

Requirements: Linux, rootful Docker Engine, and Compose v2. The Agent uses cgroups, the host filesystem, and the Docker socket. macOS / Windows Docker Desktop is not a production host-monitoring environment. Server and Agent may run on the same host or separate hosts.

### Guided setup

Run from the Lookout root and enter host IPs, Docker networks, plugins, and passwords:

```bash
bash scripts/setup.sh          # Choose Ansible / Server / Agent.
# bash scripts/setup.sh ansible
# bash scripts/setup.sh server
# bash scripts/setup.sh agent
```

On Windows, use PowerShell 7.2+:

```powershell
pwsh -NoProfile -File .\scripts\setup.ps1
```

Server / Agent modes use local Python 3. Windows Ansible mode requires `ansible-vault` in the default WSL distribution. Monitored hosts still run Linux.

Ansible mode generates a personal inventory and encrypted Vault. Server / Agent modes generate `.env` and plugin configuration. Password input is hidden. The wizard prints deployment commands without starting services. See the [setup guide](docs/setup.md) for full instructions.

The following sections describe manual Compose setup. If you used the wizard, continue with its printed commands.

### 0. Select plugins

Run once from the Lookout root; Python 3 is required:

```bash
python3 scripts/plugins.py apply             # Core only.
# python3 scripts/plugins.py apply odoo nginx # Complete enabled plugin list.
```

Odoo- and Nginx-specific parsers, dashboards, and alerts live in [plugins/](plugins/README.md) and are disabled by default. Generate configuration for each deployment directory first; Ansible handles this automatically.

### 1. Monitoring host

Run from the parent directory containing `lookout/`:

```bash
cd lookout/server
cp .env.example .env
# Set GRAFANA_ADMIN_PASSWORD and BIND_ADDR in .env.
# BIND_ADDR must be a private/VPN host IP reachable by Agents, e.g. 10.0.0.10.
# Even on a shared Server/Agent host, use a host IP reachable by containers, not 127.0.0.1.
sudo ../scripts/prepare-data.sh
# Validate configuration, then start services.
docker compose config --quiet
docker compose up -d
```

Data defaults to `server/data/`. For a different location, set `LOOKOUT_DATA_DIR` in `.env` and run `sudo ../scripts/prepare-data.sh /mnt/monitoring` with the same path. The script creates directories and permissions only; it does not format or mount disks.

Grafana binds to `127.0.0.1:3000` by default. Use `ssh -L 3000:127.0.0.1:3000 user@monitoring-host`, then open <http://localhost:3000>. When using an HTTPS reverse proxy, set `GRAFANA_ROOT_URL` to the public-facing URL.

Loki port 3100 and Prometheus port 9090 expose unauthenticated write/query APIs. Limit access to trusted private-network/VPN Agents and keep them off the public internet. Configure a VPN or authenticated TLS proxy for access across networks.

### 2. Each monitored host

Run from the parent directory containing `lookout/`:

```bash
cd lookout/agent
cp .env.example .env
# Set globally unique HOST_NAME, HOST_ROLE, LOOKOUT_ENVS, APP_NETWORK, and both push URLs.
# Use an existing application network, or create one:
docker network create app  # Only if it does not already exist.
docker compose config --quiet
docker compose up -d
```

Host/container metrics are collected automatically. Container logs require `lookout.enable=true` by default. For example, add these labels to your Compose service:

```yaml
services:
  api:
    image: your-api:your-version
    labels:
      lookout.enable: "true"
      lookout.env: prod
      lookout.service: api
      lookout.format: json
```

Recreate application containers to apply labels. Existing containers without labels can temporarily be included through the `LOOKOUT_CONTAINERS` name regex. See [labels](docs/labels.md).

### 3. Optional databases and notifications

- Databases: configure PostgreSQL, MySQL, and Redis through [targets](docs/targets.md). No database connections are enabled by default.
- Notifications: the default Alertmanager receiver sends nothing externally. Follow [alerts](docs/alerts.md) to enable Discord, Slack, Telegram, Teams, email, or webhooks.
- Nginx: use the [Nginx plugin](plugins/nginx/README.md) for safe JSON access-log output.
- Multiple hosts: deploy with [Ansible](deploy/README.md) over standard SSH.

## Dashboards and alerts

Grafana's Lookout folder includes an overview, generic application logs, and host/container/PostgreSQL dashboards. Enabling plugins adds Nginx or Odoo panels. Custom panels query `host`, `env`, `service`, and `format`, without requiring fixed container names.

By default, alerts target applications/databases with `env="prod"` and hosts with `role="prod"`. Other environments remain available in Grafana. See [alerts](docs/alerts.md) for thresholds, the 24-hour disappearance-detection limitation, and handling retired hosts. Loki retains production logs for 30 days and other environments for seven days. Prometheus retains all metrics for 30 days. Adjust retention in `.env`.

## Validation and operations

Run from the Lookout root:

```bash
# Requires local Docker, Compose v2, and Python 3; runs temporary validation containers.
./scripts/check.sh
./scripts/check.sh odoo nginx  # Include plugins.
```

After startup, check the Agent at `http://127.0.0.1:12345/-/ready` and the Server's Prometheus `/-/ready`, Loki `/ready`, and Grafana `/api/health` endpoints. See [rollout](docs/rollout.md) for complete operations, updates, and backups.

Personal `.env` files, data, credentials, Agent targets, and the local Vault path are excluded by `.gitignore`. This directory contains a standalone, general-purpose version; the original source project remains in its original location.

## Maintenance and licensing

See the root [CONTRIBUTING.md](../CONTRIBUTING.md) and [SECURITY.md](../SECURITY.md) for shared practices, and [versioning](docs/versioning.md) for Lookout-specific version and validation workflows. Original work is licensed under the [MIT License](../LICENSE). Third-party images, packages, and dashboards retain their own licenses.
