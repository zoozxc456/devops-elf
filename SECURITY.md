# Security Policy

This policy covers IAP connection management, Lookout monitoring configuration and deployment scripts, and PostgreSQL image build definitions in DevOps Elf. Report vulnerabilities in third-party services, images, and packages to their respective maintainers.

## Maintenance scope

Each project maintains its own versions. Security fixes prioritize current development code and the latest release. This collection has no shared long-term support release or commitment to backport fixes to older versions. See the root [README.md](README.md) for version sources and changelogs.

## Reporting a vulnerability privately

Do not post exploitable vulnerability details, credentials, or real configuration in public issues or pull requests.

If the repository is hosted on GitHub and private vulnerability reporting is enabled, use **Security → Report a vulnerability**. Otherwise, use a private contact method published by the maintainer. This document does not currently specify a dedicated security email address. If no private channel is available, open an issue that only requests a private contact method and contains no vulnerability details.

Include the affected project and version, environment details, reproduction steps using fictional data, impact, exploitation prerequisites, and possible mitigations. Validate findings only in test environments you own or are authorized to use.

Maintainers will assess reports and coordinate fixes and disclosure as availability permits. There is currently no fixed response deadline or bug bounty commitment.

## Shared data protection

- Keep passwords, tokens, SSH private keys, service account keys, real connection configuration, database data, and backups out of commits.
- `.env` files, inventories, Vault files, targets, shell history, and monitoring logs may contain sensitive information. Ignoring a file in Git does not encrypt it.
- Store Ansible Vault passwords separately from encrypted files. Grant deployment automation accounts only the permissions they need.
- Installation, updates, deployment, and container builds execute source code or obtain third-party dependencies. Use trusted sources and review changes.

## IAP connection management

Keep credentials out of endpoints, which are displayed in the terminal. Tunnels use `localhost` by default, but other processes on the same host may still access their ports. Close connections when finished, and protect configuration backups and exports. See the [IAP security supplement](google-iap-client-manager/SECURITY.md) for file permissions, editor behavior, and updates.

## Lookout monitoring

Keep Loki and Prometheus write and query APIs off the public internet. Restrict access to trusted private networks or VPNs, and configure an authenticated TLS proxy when needed for access across networks. Set appropriate Grafana credentials and access controls. Treat notification webhooks, database exporter credentials, and logs as sensitive data.

The Agent accesses the Docker socket, host filesystem, and cgroups. Deploy it only on trusted Linux hosts. Review the impact on host and application data before changing mounts, permissions, or collection scope. See the [Lookout README](lookout/README.md) and [operations guide](lookout/docs/rollout.md) for deployment and backup guidance.

## PostgreSQL images and backups

Restrict public access to database ports. Use dedicated accounts, appropriate network restrictions, and secure credential storage. Including pgBackRest in the image does not configure backups: repositories, WAL archiving, scheduling, retention, and restore validation require separate setup.

Check data and extension compatibility before upgrades, and validate backup and restore procedures in an isolated environment. Keep production data directories out of disposable test containers. See the [image maintenance guide](postgres18-with-pgbackrest-client/GUIDELINE.md) for project-specific requirements.

## If credentials are exposed

Revoke or rotate affected credentials first, review access logs according to your organization's procedures, then address public content, Git history, and backups. Deleting the current file cannot recall copies already obtained by others.
