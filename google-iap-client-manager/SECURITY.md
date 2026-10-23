# IAP Security Supplement

Follow the root [SECURITY.md](../SECURITY.md) for vulnerability reporting, maintenance scope, shared data protection, and exposed credential handling. This document covers behavior specific to the IAP CLI, configuration files, and local connections.

## Usage and data protection

- The tool uses the authentication state and permissions of your local `gcloud` installation. It does not store or manage Google Cloud credentials on your behalf. Access permissions and cloud connectivity remain governed by Google Cloud configuration.
- Projects, zones, instances, accounts, and internal endpoints may contain sensitive information. Protect configuration, exports, backups, and shell history, and keep them out of public repositories.
- Keep passwords, tokens, private keys, and connection strings containing credentials out of endpoints. Endpoints appear in the terminal and may be captured in screenshots, recordings, or logs.
- Tunnels specify `localhost` as the local listening address by default. Other processes on the same host may still access the port. Close connections when finished.
- Private configuration files, backups, and file exports created by the tool use `0600` permissions on Unix. On Windows, the PowerShell implementation uses ACLs restricted to the current user. These permissions do not encrypt files or prevent access by administrators or processes running as the same user.
- `iap edit` without a name opens the entire configuration in your editor. Backup files, swap files, and their permissions depend on that editor. Prefer `iap edit <name>` when changing a single connection.
- `iap export` without an output path prints configuration to the terminal. Use `iap export FILE` to create a private file. If you redirect output yourself, the shell determines the resulting file permissions.
- Installers and `iap update` execute code from the source directory. Use trusted sources and protect source and installation directories. Git updates use `--ff-only`, which does not provide source signature verification.
