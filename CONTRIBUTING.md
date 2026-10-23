# Contributing

This guide applies to the entire DevOps Elf collection. Start with [README.md](README.md) to identify the project affected by your change. Report security vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Reporting issues and proposing changes

On the project hosting platform, describe the expected behavior, actual result, reproduction steps, affected project and version, operating system, and relevant tool versions. Include sanitized configuration or logs, removing account details, internal hosts, connection strings, passwords, and tokens.

For feature proposals, explain the use case and intended workflow. Discuss compatibility and migration plans before making substantial changes to interfaces, deployment, or data formats.

## Change guidelines

- Keep each change focused on one problem. For changes spanning multiple projects, explain the impact on each project.
- Follow the existing style of each project. Use UTF-8 encoding and LF line endings for text files.
- Preserve platform compatibility: Bash 3.2+ / PowerShell 7.2+ for IAP, and Linux deployment requirements for Lookout.
- When adding or changing commands, update the relevant README, examples, and the project's `Unreleased` entries.
- Preserve confirmation prompts, private backups, and input validation. Tests must avoid personal configuration and production resources.
- Keep `.env` files, real host configuration, personal inventories, unencrypted Vault files, private keys, database data, backups, and monitoring data out of commits. Project `.gitignore` files do not cover every custom path; review your changes before committing.
- Preserve source attribution and required license notices for third-party code, dashboards, and configuration examples.

## Project development and validation

This document defines shared practices. Each project's documentation maintains its test commands, platform limitations, and release steps to avoid duplicating workflows.

| Project | Development and validation | Versioning and releases |
|---|---|---|
| Google IAP Client Manager | [Development supplement](google-iap-client-manager/CONTRIBUTING.md) | Follow the release checklist in the same document; Bash and PowerShell versions must match |
| Lookout | [Versioning and validation](lookout/docs/versioning.md), [operational verification](lookout/docs/rollout.md) | Use the Lookout version tool and `lookout-vX.Y.Z` tags |
| PostgreSQL 18 image | [Maintenance and validation guide](postgres18-with-pgbackrest-client/GUIDELINE.md) | Update versions, image tags, and upgrade notes according to image compatibility |

For documentation changes, check links, command examples, and formatting. For code or deployment changes, run the relevant tests and report any skipped checks. Passing configuration checks does not establish that a production deployment has been validated.

## Pull requests and versioning

Describe the problem, resulting behavior, validation results, and any platforms or external environments you have not verified. When working in Git, run `git diff --check` and review the diff for sensitive information before committing.

The three projects release independently: IAP keeps Bash and PowerShell versions aligned, Lookout uses its own version tool, and the PostgreSQL image follows its maintenance guide for tags and upgrade notes. Root documentation changes do not require version bumps across all projects. Preserve existing release history without inventing shared release dates.

Record project-specific feature changes in that project's changelog. Record shared documentation or cross-project changes in the root [CHANGELOG.md](CHANGELOG.md).

## License

By submitting a contribution, you confirm that you have the right to provide it and agree to license it under this collection's [MIT License](LICENSE). Third-party content remains subject to its original license terms.
