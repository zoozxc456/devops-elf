# Continuous Integration

GitHub Actions validates this repository on pull requests, pushes to `main` or `master`, and manual runs through the Actions tab. All workflows use read-only repository permissions. They require no cloud credentials and do not publish images or deploy services.

## Workflows

| Workflow | Checks | Runner |
|---|---|---|
| [IAP CI](workflows/iap-ci.yml) | Existing installation, configuration, connection management, export, and update tests for Bash and PowerShell | Ubuntu 24.04 and macOS 15, Python 3.12 |
| [Lookout CI](workflows/lookout-ci.yml) | Version consistency, setup/plugin tests, real test Vault encryption, Ansible syntax, and core / Odoo+Nginx configuration checks | Ubuntu 24.04, Python 3.12 |
| [PostgreSQL Image CI](workflows/postgres-ci.yml) | Image build, pgBackRest, pgvector package, directory ownership, disposable database startup, and vector extension/query checks | Ubuntu 24.04 |
| [Repository CI](workflows/repository-ci.yml) | Local Markdown link targets and workflow validation with actionlint | Ubuntu 24.04 |

Project workflows run for changes under their own directory or to their workflow file. Markdown-only changes use Repository CI without running project builds. Repository CI runs for every pull request and default-branch push so file deletions that break documentation links are also checked. Each workflow can be run manually regardless of path filters.

New commits to the same ref cancel older runs of the same workflow. Jobs have timeouts, and matrix failures do not cancel sibling jobs.

## Dependencies and test scope

IAP installs YAML support and verifies that jq, zsh, and PowerShell are available before running tests. Linux jobs use the PowerShell supplied by the GitHub-hosted runner; macOS installs it with Homebrew if absent. The macOS suite invokes `/bin/bash`, covering the system Bash implementation. Windows ACL and WSL behavior are not covered by these workflows and still require Windows validation.

Lookout installs Ansible and YAML support and requires PowerShell and Docker Compose before running tests. Its Ansible syntax check uses a temporary test-only Vault and the project's collection requirements. Configuration jobs validate core-only and Odoo+Nginx setups through the existing isolated `scripts/check.sh`. They do not connect to real databases, deploy to remote hosts, or send notifications.

The PostgreSQL job builds using the project's Docker context and `.dockerignore`. Its temporary database exposes no host port and uses disposable storage. Health checks use TCP to wait for the final server rather than the initialization-only Unix socket. Containers and anonymous volumes are removed afterward. The job does not validate remote backup repositories, WAL archiving, restore procedures, or additional CPU architectures.

The documentation checker validates local inline and reference link targets in tracked and unignored Markdown files, excluding fenced code examples. It does not validate heading anchors or request external URLs. actionlint checks workflow syntax and expressions, and uses ShellCheck for embedded shell commands. The workflow requires ShellCheck to be present before validation.

## Local checks

From the repository root:

```bash
python3 .github/scripts/check-docs.py
# Includes ShellCheck; requires Docker and may download the validation image.
docker run --rm -v "$PWD:/repo:ro" -w /repo rhysd/actionlint:1.7.12 -color
```

Project test and validation commands remain documented in the guides linked from [CONTRIBUTING.md](../CONTRIBUTING.md). Dependencies and Docker must be installed locally for the corresponding checks.

## Branch protection and future delivery

Repository CI jobs run independently of project path filters. If enabling required checks, use these always-triggered jobs as the initial baseline. A project workflow skipped by path filters can leave its required check pending; avoid requiring every path-filtered workflow for all pull requests without adding an always-running aggregate check.

Automatic releases, registry uploads, and deployments are outside this initial setup. Add them separately once registry destinations, release tags, and deployment environments are defined.
