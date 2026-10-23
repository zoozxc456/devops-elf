# Google IAP Client Manager

**English** | [繁體中文](README.zh-TW.md)

Manage Google Cloud VM connections over IAP SSH and TCP tunnels with the `iap` command. Available in Bash and native PowerShell.

[Changelog](CHANGELOG.md) · [Contributing](../CONTRIBUTING.md) · [Development supplement](CONTRIBUTING.md) · [Security supplement](SECURITY.md) · [MIT License](LICENSE)

Save frequently used VMs and port tunnels in a configuration file instead of searching shell history. Starting a tunnel prints its URLs or database connection strings, ready to use once the connection is established.

The CLI currently displays Traditional Chinese messages. Example output:

```text
$ iap app-web
→ [app-web] localhost:18080  ⇢  app-vm:8080  連線中…
  連線入口（tunnel 建立後可用）：
  前台  http://localhost:18080/
  健康檢查  http://localhost:18080/health

✔ [app-web] 已連線  localhost:18080  ⇢  app-vm:8080
  (Ctrl-C 結束)
```

## Requirements

| Purpose | Bash (macOS / Linux) | PowerShell (Windows / macOS / Linux) |
|---|---|---|
| Runtime | Bash 3.2+ and standard Unix utilities | PowerShell 7.2+; Windows PowerShell 5.1 is unsupported |
| Connections | Google Cloud CLI (`gcloud`) | Google Cloud CLI (`gcloud`) |
| Plain-text configuration | No additional format packages | Native support |
| JSON configuration | `jq`; wizard output also requires Python 3 | Native support |
| YAML configuration | `jq`, plus mikefarah `yq` or Python 3 + PyYAML | Native support for JSON syntax; general YAML requires mikefarah `yq` |
| Editing individual connections, removing, resetting, uninstalling | Python 3 | Native support |
| Optional features | `fzf` fuzzy selection; Git for updating Git sources | Git for updating Git sources |

The tool invokes local `gcloud`. Have an administrator configure the target project, VM, IAP connectivity, and permissions, then authenticate:

```bash
gcloud auth login
```

Using `-` for project / zone uses the current gcloud configuration. Set explicit values when working across projects.

## Installation and quick start

```bash
# Obtain the source, then enter the project directory.
cd google-iap-client-manager
bash install.sh --setup  # Install to ~/.local/bin and launch the setup wizard.
```

Load the shell configuration shown by the installer or open a new terminal, then connect using names created in the wizard:

```bash
iap ls            # Check the connection list.
iap show app-web  # Show endpoints without connecting.
iap app-web       # Start a tunnel; replace with your configured name.
iap app-vm        # Connect over SSH; replace with your configured name.
```

Run `iap` without a name for an interactive menu. Tunnels run in the foreground; use `Ctrl-C` to stop them. Endpoint hints appear immediately; actual availability depends on the gcloud connection result.

Update:

```bash
iap update  # Update the source and copy the new version into the current bin directory.
iap version
```

Installation prints the installed version. Updates print the previous and resulting versions, including when the synchronized version is unchanged.

Installation records the source directory in `.iap/bash-source` under the bin directory (`powershell-source` for PowerShell). If the source is a Git checkout, `iap update` checks for uncommitted changes, runs `git pull --ff-only --tags`, and refreshes the installed program, wizards, and completions. For a plain directory, it synchronizes that directory's current contents. Updates do not run setup or change connection configuration. Connections continue working after source removal, but updating requires reinstalling from the new source location to refresh the record.

The Bash client requires `bash` and, for connections, `gcloud`. The `remove`, `reset`, `uninstall`, and `edit <name>` commands also require Python 3. Optional tools include `fzf` for fuzzy selection, `jq` for JSON/YAML configuration, and `yq` or Python 3 + PyYAML for YAML.

## Interactive setup and new connections

To add an SSH connection or tunnel to existing configuration:

```bash
iap new
# Or specify a configuration file:
iap new --config /path/to/hosts
```

Enter a connection name, `ssh` / `tunnel`, project, zone, and VM instance; tunnels also require ports. You can add multiple endpoints, with one connection added per invocation. `new` preserves existing connections, backs up the original file, rejects duplicate names, and writes nothing if canceled. Project / zone default to `-`, using gcloud configuration; enter explicit values when needed.

Plain-text configuration preserves existing content. JSON/YAML data is retained but serialized as JSON syntax, so YAML comments and formatting are available only in the backup. Adding to general YAML requires Python 3 + PyYAML or mikefarah yq on Bash, and mikefarah yq on PowerShell. Use `setup` for initial creation or a complete rebuild.

For initial setup or a complete rebuild:

```bash
# Before installation, run from the project root:
bash scripts/setup.sh

# After installation, run from any directory:
iap setup

# Choose an output path, for example in a temporary directory:
iap setup --config /tmp/iap/hosts
```

Enter shared project / zone defaults, connection names, SSH or tunnel types, per-connection project / zone, and VM instances. Tunnels also require remote/local ports. You can add multiple endpoints and connections. SSH instances may use `user@instance`; tunnels use only the instance name.

Press Enter to accept displayed defaults. Use `-` for project / zone to use gcloud configuration. The wizard does not change gcloud configuration, authenticate, or connect. It prints inspection and connection commands when finished. Before connecting, run `gcloud auth login` and ensure your account has the required IAP / SSH access.

By default, the wizard creates a plain-text `hosts` file with no additional format dependencies. Existing YAML/JSON filenames are retained, with Python 3 producing JSON syntax, which is also valid YAML. Reading those files still requires the format dependencies above. Rebuild mode does not reuse existing fields: overwrite defaults to cancel; after confirmation, the file is rebuilt from new input and the original saved as a sibling `.backup-*` file. Configuration and backups use `0600` permissions. Canceling writes nothing, and symbolic link targets are rejected.

Install without setup, or customize the location:

```bash
bash install.sh
bash install.sh --bin-dir "$HOME/bin" --setup
# The BIN_DIR environment variable is also supported.
BIN_DIR="$HOME/bin" bash install.sh
```

Installation persistently adds the bin directory to PATH by default. For zsh, it writes to `${ZDOTDIR:-$HOME}/.zshrc`. For Bash, it updates `.bashrc` and the first existing login file among `.bash_profile`, `.bash_login`, and `.profile`, creating `.bash_profile` if none exists. Existing files are backed up, and repeated installation avoids duplicate entries. Open a new terminal or run the printed `source` command to load the change.

Use `--shell bash` / `--shell zsh` to select a shell, `--rc-file PATH` to choose a file, or `--no-path` to copy files without changing PATH. `iap update` automatically skips PATH setup. Add Tab completion separately using the installer instructions.

Installation copies `iap` directly into the bin directory and setup/completion files into its `.iap/` directory. Installed copies remain usable after moving or removing source files. Reinstallation updates those copies and replaces legacy `iap` symlinks with regular files. It refuses to overwrite existing regular files it cannot identify as belonging to this tool.

## PowerShell (Windows / macOS / Linux)

Requires **PowerShell 7.2+** (`pwsh`); Windows PowerShell 5.1 is unsupported. Configuration and connections use native PowerShell without Bash, WSL, Python, or jq. Actual connections require `gcloud`.

Install and configure from the project root:

```powershell
pwsh -NoProfile -File .\install.ps1 -Setup
# Customize the install location:
pwsh -NoProfile -File .\install.ps1 -BinDir "$HOME\bin" -Setup

# Create configuration without installing:
pwsh -NoProfile -File .\scripts\setup.ps1
pwsh -NoProfile -File .\scripts\setup.ps1 -Config "$HOME\iap-config\hosts.json"
```

The installer copies `iap.ps1` into `$HOME/.local/bin`, with setup, shared functions, and completion under `.iap/`. Installed files are independent of the source directory. Reinstallation updates this tool's copies and replaces legacy launchers with the complete program. `iap update` updates Git sources or synchronizes local sources, then refreshes the current installation.

On Windows, installation updates the user PATH without administrator privileges. On macOS / Linux, it writes to `$PROFILE.CurrentUserAllHosts`, backing up existing content and avoiding duplicates. Both update the installer process's PATH. Running `& ./install.ps1` in an existing PowerShell session makes the command available immediately; when using a child process via `pwsh -File`, open a new parent terminal session afterward. Use `-NoPath` to skip PATH setup, or `-ProfilePath PATH` to choose a profile. Specifying a profile on Windows also switches persistence to that file. Add completion to `$PROFILE` using the printed instructions. Without PATH setup, invoke the script directly:

```powershell
pwsh -NoProfile -File .\iap.ps1 setup
pwsh -NoProfile -File .\iap.ps1 ls
pwsh -NoProfile -File .\iap.ps1 app-vm

# After adding the install directory to PATH:
iap setup -Config "$HOME\iap-config\hosts.json"
iap new -Config "$HOME\iap-config\hosts.json"
$env:IAP_CONF = "$HOME\iap-config\hosts.json"
iap ls
iap show app-web
iap app-web

# Completion; add to $PROFILE, adjusting the path to your installation:
. "$HOME\.local\bin\.iap\completions\iap.ps1"
```

The client shares Bash's configuration search order, `IAP_CONF`, `XDG_CONFIG_HOME`, and rebuild/backup rules. The PowerShell wizard writes YAML files using JSON syntax, requiring no YAML package; handwritten general YAML requires mikefarah `yq`. Output uses UTF-8 without BOM and LF line endings. Unix permissions are `0600`; Windows configuration and backups use ACLs restricted to the current user.

PowerShell supports numeric menus, direct SSH/tunnel connections, and the management commands below. `import`, `to-yaml`, and fzf menus are currently Bash-only. On macOS / Linux with both implementations installed, use `iap.ps1` to explicitly select PowerShell.

## Managing connections and uninstalling

Export the currently selected configuration, chosen through `IAP_CONF` or the default search order:

```bash
iap export                         # Print configuration without modifying files.
iap export ~/iap-backup/hosts       # Export to a file.
iap export --output ~/iap-backup/hosts
```

PowerShell supports `iap export FILE` and `iap export -Output FILE`. File exports copy original content exactly, retaining comments, formatting, line endings, and BOM without converting YAML/JSON. Keep the original format for exported files. Existing output defaults to no overwrite; explicit confirmation creates a backup before replacement. Output cannot be the current configuration file or a symbolic link. Unix exports use `0600`; Windows uses private ACLs. Only the selected configuration file is exported, without historical backups or installation metadata.

```bash
iap edit oneclick-db    # Edit only this connection, including endpoints.
iap remove oneclick-db  # Remove this connection, including endpoints.
iap reset               # Clear all connections in the selected configuration.
iap uninstall           # Remove this shell's installation, preserving configuration.
```

When `setup` finds existing configuration, it displays the path and warns about the complete rebuild. It defaults to no overwrite and backs up the original after confirmation. Use `new` to add connections and `edit <name>` to modify one connection.

`edit <name>` copies the selected connection into a private temporary file and opens `$EDITOR` (Bash defaults to `vi`; PowerShell defaults to Notepad on Windows and `vi` elsewhere). After you save and close the editor, it validates names, types, and ports, then asks whether to save. Keep the original name, and do not add a second connection or modify shared defaults. Unchanged content, cancellation, editor failure, or invalid format leaves configuration untouched. `iap edit` without a name opens the entire configuration directly.

`remove`, `reset`, and `uninstall` show their scope and require explicit `y` / `yes`; Enter cancels. `reset` clears only the selected file's connections, retaining JSON/YAML defaults and other shared fields. Other configuration files and backups are unaffected.

Edits, removals, and resets create sibling `.backup-*` files with `0600` permissions on Unix or private ACLs on Windows. JSON/YAML management operations serialize data as JSON syntax; use backups to recover YAML comments and formatting. Writing stops if another process changes configuration during the operation.

`uninstall` is available for copy-based installations: Bash removes `iap` and its supporting files; PowerShell removes `iap.ps1` and its supporting files. It preserves the other implementation when both are installed, plus user configuration, backups, and source files. Manually remove completion-loading lines from shell rc files or `$PROFILE`.

## Commands

| Command | Description |
|---|---|
| `iap help` / `iap --help` / `iap -h` | Show help |
| `iap export [FILE]` | Export configuration in its original format; print it when FILE is omitted |
| `iap setup [--config PATH]` | Create/rebuild configuration interactively, with backups |
| `iap new [--config PATH]` | Add one SSH/tunnel connection, retaining and backing up existing configuration |
| `iap` | Interactive menu, using fzf when available |
| `iap <name> [-- ssh arguments]` | Connect directly |
| `iap show <name>` | Display endpoints without connecting |
| `iap ls` | List hosts |
| `iap edit [name]` | Edit the entire configuration or one connection |
| `iap remove <name>` | Confirm, back up, and remove one connection |
| `iap reset` | Confirm, back up, and clear all connections in the selected configuration |
| `iap uninstall` | Confirm and remove this implementation's installation, retaining configuration |
| `iap import` | Extract gcloud commands from shell history |
| `iap to-yaml` | Convert plain-text configuration to YAML |
| `iap version` / `iap update` | Show the version / update sources and refresh installed copies |

## Configuration files

The default directory is `${XDG_CONFIG_HOME:-$HOME/.config}/iap`. The first existing file is selected in this order: `hosts.yaml`, `hosts.yml`, `hosts.json`, `hosts`. Override it with `IAP_CONF=/path/to/file`. The wizard's `--config PATH` takes precedence over `IAP_CONF` and affects only that invocation's output. When creating configuration elsewhere, set `IAP_CONF` for subsequent commands as well.

See [`examples/hosts.yaml`](examples/hosts.yaml) for YAML. Plain-text format:

```text
# name       type    project      zone          instance        [remote_port] [local_port]
app-web   tunnel  my-project  us-central1-a  app-vm  8080  18080
  > Health http://localhost:{port}/health
app-vm  ssh     my-project  us-central1-a  app-vm
```

Plain-text fields are whitespace-separated and cannot contain spaces. `type` is `ssh` or `tunnel`. Tunnels require a remote port; the local port defaults to it. Endpoint lines start with `>` and belong to the preceding connection. `{port}` / `{rport}` expand to local/remote ports. Endpoints are display-only; they do not launch browsers or database clients.

YAML/JSON uses a top-level `hosts` object, with optional `defaults.project` / `defaults.zone`. Connection `type` defaults to `ssh`, and `instance` defaults to the connection name. See the linked example for details. Avoid command names such as `setup`, `new`, `help`, and `export` as connection names.

Configuration defaults to a directory outside the source tree. Keep real host settings, credentials, exports, and backups out of commits; `.gitignore` cannot cover every custom filename. `iap update` changes programs and supporting files without modifying connection configuration.

## Tab completion

```bash
source ~/.local/bin/.iap/completions/iap.bash   # Add to ~/.bashrc or ~/.zshrc.
```

## Troubleshooting

| Symptom | Check |
|---|---|
| `iap` is unavailable after installation | Open a new terminal or load the shell rc/profile shown by the installer; verify the bin directory is on PATH |
| Configuration is missing or the list is unexpected | Check `IAP_CONF`, `XDG_CONFIG_HOME`, and the search order; `--config` affects only that wizard invocation |
| YAML/JSON cannot be read | Install the required format tools; `yq` must be the mikefarah version |
| gcloud rejects a connection | Check account authentication, project, zone, VM name, IAP/SSH permissions, and cloud networking |
| Local port is already in use | Change `local_port` with `iap edit <name>` or stop the process using it |
| `iap update` fails | Retain the source directory, resolve uncommitted changes in Git sources, and reinstall after moving sources |
| YAML comments disappear after changes | Management commands serialize JSON syntax; recover original comments and formatting from `.backup-*` |

## Development and contributions

See [CONTRIBUTING.md](CONTRIBUTING.md) for development, test coverage, and release checks. Report security issues privately through the root [SECURITY.md](../SECURITY.md); see the [security supplement](SECURITY.md) for IAP-specific behavior.

## Validation

```bash
python3 -m unittest discover -s tests -v
```

Tests use temporary configuration and substitute gcloud commands, without connecting to Google Cloud or modifying personal configuration. PowerShell tests require `pwsh` on PATH and are skipped when unavailable. Verify Windows ACL branches on Windows.

## License

This project is licensed under the [MIT License](LICENSE).
