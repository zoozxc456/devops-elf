# Ansible Deployment

**English** | [繁體中文](README.zh-TW.md)

Deploy the current `server/` and `agent/` directories from a control host to Linux Docker hosts over standard SSH. This workflow is independent of GCP, any particular VPN, or application. Remote hosts need Docker Engine and Compose v2 installed, and the SSH user must have sudo access. The playbook does not install Docker, create application networks, or create database accounts.

## Guided setup

After installing `ansible-core`, run from the Lookout root:

```bash
bash scripts/setup.sh ansible
```

On Windows, you can also use PowerShell 7.2+ from the Lookout root:

```powershell
pwsh -NoProfile -File .\scripts\setup.ps1 -Mode ansible
```

Windows setup requires `ansible-vault` in WSL. Run subsequent deployment from a Linux/WSL control host; see the [Windows setup guide](../docs/setup.md).

Enter SSH, host, Docker network, plugin, and Grafana settings. The wizard generates `deploy/inventory.local.yml`, creates an encrypted Vault on first use, and preserves any existing encrypted Vault. Use `-i inventory.local.yml` when deploying. See the [setup guide](../docs/setup.md) for operation and backups.

## Manual setup

Run from the Lookout root:

```bash
pipx install ansible-core
cd deploy
ansible-galaxy collection install -r requirements.yml -p .collections
# Update SSH users/hosts in inventory.yml and monitoring IP / APP_NETWORK in group_vars/all/main.yml.
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
# Set a real Grafana password; environment values cannot contain single quotes or newlines.
ansible-vault encrypt group_vars/all/vault.yml
ansible all -m ping --ask-vault-pass
ansible-playbook site.yml --syntax-check --ask-vault-pass
ansible-playbook site.yml --ask-vault-pass
```

The `192.0.2.x` addresses in `inventory.yml` are documentation examples; replace them with your hosts. The `lookout_server` group deploys monitoring services; `lookout_agent` deploys Alloy. A host alias may appear in both groups. Add a dedicated monitoring host to the Agent group as well to monitor its disk and memory.

Use `-i inventory.local.yml` for a personal inventory excluded from Git. Use `--limit app-01` for one host, or `--tags agent` / `--tags server` to select a role. The Vault preflight runs on localhost, checks only the header, and does not display contents; the Vault must be encrypted. `--check --diff` can preview changes to existing deployments, but is incomplete on a first deployment without directories or Compose files and cannot establish successful validation.

## Per-host settings

For example, create `host_vars/app-01.yml`:

```yaml
host_name: app-01
host_role: staging
app_network: app
lookout_envs: staging|dev
lookout_containers: ""
lookout_agent_targets: |
  lookout_postgres "main" {
    env        = "staging"
    instance   = "postgres-main"
    dsn        = sys.env("PG_DSN_MAIN")
    forward_to = [prometheus.relabel.gate.receiver]
  }
```

Store DSNs in the encrypted Vault, keyed by inventory name:

```yaml
vault_lookout_agent_env:
  app-01:
    PG_DSN_MAIN: postgresql://monitoring:URL_ENCODED_PASSWORD@postgres:5432/postgres?sslmode=disable
```

Use `lookout_agent_env` for additional non-sensitive variables; matching Vault values take precedence. Extra variables cannot override core HOST_NAME / APP_NETWORK / push URLs. DSNs and targets are optional; no database connections are enabled by default.

## Server settings

Override these in the monitoring host's host_vars:

```yaml
lookout_data_dir: /mnt/monitoring  # Mount storage first; the role only creates directories and permissions.
# For external Grafana access, keep the localhost binding and use an HTTPS reverse proxy.
grafana_bind_addr: 127.0.0.1
grafana_root_url: https://grafana.example.com
grafana_timezone: browser
prometheus_retention: 30d
loki_retention: 720h
loki_retention_nonprod: 168h
```

Notifications are disabled by default. Copy `server/alertmanager/alertmanager.yml` to a personal configuration file, uncomment the channels you need, and set `lookout_alertmanager_config` to that file's absolute path on the control host. Store secrets in Vault:

```yaml
vault_alertmanager_secrets:
  discord_webhook_url: https://discord.com/api/webhooks/REPLACE/REPLACE
```

Each key maps to a file under the remote `server/secrets/` directory. When removing a notification channel, manually remove any unused remote secret. Personal configuration should reference secret paths rather than embed tokens.

## Applying changes

| Change | Behavior |
|---|---|
| Prometheus configuration/rules | SIGHUP reload |
| Loki rules / Grafana dashboards | Automatic reload |
| Grafana provisioning | Recreate Grafana |
| Loki / Alertmanager configuration or notification secrets | Recreate the affected container |
| Alloy core / modules / targets | Recreate Alloy |
| Compose / .env | Compose up recreates affected services |

Synchronizing Server rule and dashboard directories also removes remote files that no longer exist in the source. Keep custom content in your deployment source. Deployment uses current local files; review them and complete [validation](../README.md) first. Configure SSH jump hosts, VPN, or GCP IAP through inventory `ansible_ssh_common_args` as needed.

## Optional plugins

Set `lookout_plugins: [odoo, nginx]` in each host's host_vars; the default is `[]`. Agent and Server lists may differ: enable required dashboards/alerts on the Server and actual parsers on Agents. Ansible runs Python 3 on the control host to generate configuration, so manual apply is unnecessary. See [plugins](../plugins/README.md) for the structure.

## Deployment versions

Roles copy the source VERSION to remote `{{ lookout_root }}/server/VERSION` or `{{ lookout_root }}/agent/VERSION`. They are recorded separately to identify partial updates. See the [versioning guide](../docs/versioning.md) for version and release rules.
