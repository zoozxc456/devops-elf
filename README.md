# DevOps Elf

**English** | [繁體中文](README.zh-TW.md)

A little elf for everyday DevOps — a growing collection of tools, scripts, and infrastructure essentials.

The collection currently includes Google Cloud IAP connection management, Lookout (Grafana + Loki + Alloy + Prometheus), and a PostgreSQL 18 image with pgBackRest and pgvector. Each project can be used independently, with more tools to come.

[Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [MIT License](LICENSE)

## Projects

| Project | Purpose | Requirements | Version source |
|---|---|---|---|
| [Google IAP Client Manager](google-iap-client-manager/README.md) | Manage IAP SSH and TCP tunnels with setup wizards, endpoint hints, configuration export, and connection management | Bash 3.2+ or PowerShell 7.2+; gcloud for connections | `VERSION` in `iap` and version output in `iap.ps1` |
| [Lookout](lookout/README.md) | A self-hosted Grafana + Loki + Alloy + Prometheus monitoring stack for metrics and logs, with Alertmanager for alerts, optional Odoo / Nginx plugins, and Ansible deployment | Linux, Docker Engine, and Compose v2; setup tools require Python, PowerShell, or Ansible depending on the mode | [lookout/VERSION](lookout/VERSION) |
| [PostgreSQL 18 image](postgres18-with-pgbackrest-client/README.md) | Extend `postgres:18` with pgBackRest, pgvector, and CA certificates | Docker capable of building and running Linux containers | Image version in the project's [changelog](postgres18-with-pgbackrest-client/CHANGELOG.md) and README |

Projects maintain their own versions and configuration. Choose the tools you need and follow their setup instructions. IAP can connect to cloud hosts, and Lookout can monitor hosts and databases; integration with the PostgreSQL image requires your own configuration.

## Repository layout

```text
devops-elf/
├── README.md
├── README.zh-TW.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── SECURITY.md
├── google-iap-client-manager/        # IAP CLI, installers, and configuration tools
├── lookout/                          # Server / Agent, plugins, Ansible, and docs
└── postgres18-with-pgbackrest-client/ # Dockerfile and database image documentation
```

## Documentation

All README pages are available in English and Traditional Chinese. Shared contribution and security policies are in English; other detailed maintenance guides currently remain in Traditional Chinese. When updating a README, keep project listings, commands, and links consistent across both languages.

| Document | Scope |
|---|---|
| README | The root provides an overview; project READMEs cover installation, configuration, and usage |
| CHANGELOG | The root tracks shared and cross-project changes; project changelogs track their own releases |
| CONTRIBUTING | Shared practices live at the root; project-specific workflows live in the [IAP development guide](google-iap-client-manager/CONTRIBUTING.md), [Lookout versioning guide](lookout/docs/versioning.md), and [image maintenance guide](postgres18-with-pgbackrest-client/GUIDELINE.md) |
| SECURITY | The root defines reporting and shared policies; the [IAP security supplement](google-iap-client-manager/SECURITY.md) covers local files and connections |
| LICENSE | The root MIT license covers original work; IAP retains a copy for independent distribution |

When distributing a project separately, include the applicable license and required copyright notices, and update links that refer to the repository root. Third-party content retains its original license.

## Getting started

Run each example from the repository root. Obtain the source and install the requirements for your chosen project first.

### Google Cloud connection management

macOS / Linux:

```bash
cd google-iap-client-manager
bash install.sh --setup
# Load the shell configuration shown by the installer or open a new terminal:
iap ls
```

PowerShell:

```powershell
Set-Location google-iap-client-manager
pwsh -NoProfile -File ./install.ps1 -Setup
# Open a new PowerShell session:
iap ls
```

Installation adds the binary directory to your user PATH by default. `--setup` / `-Setup` launches the configuration wizard. Complete gcloud authentication and IAP / SSH access configuration before connecting; the wizard only creates configuration. See the [IAP README](google-iap-client-manager/README.md) for formats, platform differences, and connection commands.

### Lookout — Grafana + Loki + Alloy + Prometheus

```bash
cd lookout
bash scripts/setup.sh
```

Choose Ansible, Server, or Agent, generate your configuration, and follow the deployment commands printed by the wizard. Start services using those commands after reviewing the configuration. Monitored hosts must run Linux. See the [Lookout README](lookout/README.md) for architecture, Compose deployment, database targets, notifications, and plugins, or the [Ansible guide](lookout/deploy/README.md) for multiple hosts.

### PostgreSQL image

```bash
cd postgres18-with-pgbackrest-client
docker build -f dockerfile -t postgres18-with-pgbackrest-client:1.1.0 .
docker run --rm postgres18-with-pgbackrest-client:1.1.0 pgbackrest version
```

This builds the image and checks the tool version. To run a database, configure storage, pgBackRest, and extensions as described in the [image README](postgres18-with-pgbackrest-client/README.md). Backup scheduling and a repository host require separate configuration.

## Continuous integration

GitHub Actions runs project-specific tests for IAP, Lookout, and the PostgreSQL image, plus shared documentation and workflow checks. Project jobs are filtered by changed paths; all workflows also support manual runs. See the [CI guide](.github/CI.md) for coverage, triggers, and limitations.

## Validation and maintenance

Follow the project-specific checks linked from [CONTRIBUTING.md](CONTRIBUTING.md). Shared documentation and cross-project changes belong in the root changelog; each project maintains its own feature and release history.

Read the relevant guide before running setup, installation, containers, or Ansible deployment. Keep real configuration, credentials, data, backups, and Vault files out of source control. See [SECURITY.md](SECURITY.md) for reporting and operational guidance.

## License

Original code and documentation in this collection are licensed under the [MIT License](LICENSE). Third-party images, packages, dashboards, and other included content remain subject to their respective licenses and copyright notices.
