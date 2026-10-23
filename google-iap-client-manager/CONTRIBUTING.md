# IAP Development Supplement

See the root [CONTRIBUTING.md](../CONTRIBUTING.md) for shared issue reporting, pull request practices, data protection, and contribution licensing. This document covers IAP-specific development, testing, and releases. For usage, see [README.md](README.md).

## Local development

Run commands from the project root after obtaining the source. The Bash implementation must remain compatible with Bash 3.2; the PowerShell implementation requires PowerShell 7.2+. Tests use Python 3's standard-library `unittest` module. Full format and platform coverage also requires `jq`, YAML parsing tools, and `pwsh`.

You can run the clients directly without installing them:

```bash
bash ./iap help
bash ./iap version
python3 -m unittest discover -s tests -v
```

```powershell
pwsh -NoProfile -File ./iap.ps1 help
pwsh -NoProfile -File ./iap.ps1 version
python -m unittest discover -s tests -v
```

Use a separate configuration for manual testing to protect your everyday connection settings:

```bash
IAP_CONF=/tmp/iap-dev/hosts bash ./iap setup
IAP_CONF=/tmp/iap-dev/hosts bash ./iap ls
```

```powershell
$env:IAP_CONF = Join-Path ([IO.Path]::GetTempPath()) 'iap-dev/hosts'
pwsh -NoProfile -File ./iap.ps1 setup
pwsh -NoProfile -File ./iap.ps1 ls
```

When testing installation, use a separate directory and skip PATH changes. For example, run `bash install.sh --bin-dir /tmp/iap-dev/bin --no-path` or `./install.ps1 -BinDir (Join-Path ([IO.Path]::GetTempPath()) 'iap-dev/bin') -NoPath`.

The wizard only writes configuration; selecting an actual connection invokes `gcloud`. Automated tests use temporary configuration and substitute gcloud commands, so no Google Cloud account is required. PowerShell tests are skipped when `pwsh` is unavailable; report skipped checks in your submission. Windows ACL behavior must be verified on Windows; Unix tests do not cover it.

## Code structure and change guidelines

| Path | Purpose |
|---|---|
| `iap` / `iap.ps1` | CLI, configuration loading, menus, connections, and updates |
| `install.sh` / `install.ps1` | Copy-based installation, source records, and PATH configuration |
| `scripts/setup.sh` / `scripts/setup.ps1` | Wizards for creating configuration and adding connections |
| `scripts/manage.py` / `scripts/manage.ps1` | Editing individual connections, removing connections, resetting configuration, and uninstalling |
| `scripts/common.ps1` | Shared PowerShell configuration and file handling |
| `completions/` | Bash / zsh and PowerShell completion |
| `examples/hosts.yaml` | Public configuration example without real infrastructure details |
| `tests/` | Installation, configuration, management, export, and update tests |

- Preserve Bash 3.2 compatibility; avoid features requiring Bash 4+.
- Check both shell implementations when changing shared commands. Document platform-specific features.
- When adding commands, update help text, completions, reserved names, README, and CHANGELOG.
- Pass user input as arguments rather than executing configuration content as code.
- Preserve confirmation prompts, private backups, symbolic link checks, and configuration change detection.
- Add meaningful regression tests for behavior changes. Tests must not depend on real cloud resources or personal configuration.

## Release checklist for maintainers

1. Review test results and differences between Bash, PowerShell, and supported platforms.
2. Update `VERSION` in `iap` and the version output in `iap.ps1`. Keep both versions aligned.
3. Move pending `Unreleased` entries into a new version section with the actual release date, then retain an empty `Unreleased` section.
4. Update related documentation, review the changes in Git, and commit them.
5. Create an annotated tag with `git tag -a iap-vX.Y.Z -m "IAP X.Y.Z"`, then push commits and tags according to the project's remote and branch configuration.

Use `iap-vX.Y.Z` in this collection's shared repository to distinguish IAP releases from Lookout and image releases. A standalone repository may follow its existing tag convention. Versions use `MAJOR.MINOR.PATCH`. Update both shell versions together, and keep unreleased features out of published release entries.
