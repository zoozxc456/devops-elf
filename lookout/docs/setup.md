# 引導式設定精靈

在 lookout 根目錄執行，選擇 Ansible、直接部署 Server 或直接部署 Agent：

```bash
bash scripts/setup.sh
```

支援 macOS 內建 Bash 3.2 與 Linux Bash。需要 Python 3；Ansible 模式另需 `ansible-vault`（先安裝 `ansible-core`，確認指令在 PATH）。精靈只建立設定，不會連線遠端、安裝 Docker、建立網路或啟動服務。

## PowerShell 版（Windows）

需要 **PowerShell 7.2+**（`pwsh`），不使用 Windows 內建的 PowerShell 5.1。在 lookout 根目錄執行：

```powershell
pwsh -NoProfile -File .\scripts\setup.ps1
# 或直接選模式：
pwsh -NoProfile -File .\scripts\setup.ps1 -Mode ansible
pwsh -NoProfile -File .\scripts\setup.ps1 -Mode server
pwsh -NoProfile -File .\scripts\setup.ps1 -Mode agent
```

尚未安裝 PowerShell 7，可依 [Microsoft 安裝文件](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows) 使用 WinGet：

```powershell
winget install --id Microsoft.PowerShell --source winget --installer-type wix
```

與 Bash 版共用相同設定格式與插件機制：隱藏密碼輸入、既有設定備份、保留既有加密 Vault。PowerShell 版輸出 UTF-8（無 BOM）與 LF 換行；Unix 上設定檔權限為 0600，Windows 上設定檔、備份與暫存秘密目錄使用僅目前使用者可存取的 ACL。

**Ansible 模式：** Windows 不原生支援作為 Ansible 控制端，因此本精靈透過預設 WSL 發行版的 `ansible-vault` 加密；須先在 WSL 安裝 Python 3、ansible-core，並確認 `ansible-vault` 在 WSL 的 PATH。Windows 路徑透過 `wslpath` 轉換，密碼不經命令列傳遞。後續部署指令也需在 Linux／WSL 的 deploy/ 目錄執行；SSH key、ssh-agent 與 sudo 設定使用該控制端的環境。正式控制端建議使用 Linux；WSL 的支援範圍見 [Ansible Windows 文件](https://docs.ansible.com/projects/ansible-core/devel/os_guide/intro_windows.html)。

**Server / Agent 模式：** 使用 Windows 本機 Python 3（支援 `python3`、`python`、`py -3`）產生 `.env` 與插件產物，無需 WSL。目標仍是 Linux Docker 主機；畫面詢問的資料目錄請填目標 Linux 路徑，例如 `/opt/lookout/server/data`。產物須連同完整 Lookout 程式碼放到該主機，這個模式不會在 Windows 啟動主機監控服務。複製後請在目標 Linux 的 lookout/ 執行 `chmod 600 server/.env` 或 `chmod 600 agent/.env`，Windows ACL 不會自動轉成 Unix 權限。

可將設定輸出到其他資料夾：

```powershell
pwsh -NoProfile -File .\scripts\setup.ps1 -Mode agent -OutputDir 'C:\Lookout Config'
pwsh -NoProfile -File .\scripts\setup.ps1 -Help
```

PowerShell 版 Ansible inventory 採用 JSON 語法寫入 `.yml`（JSON 是合法 YAML），Ansible 可直接讀取，不需要安裝額外 PowerShell 模組。其餘欄位與後續部署步驟如下。

## Ansible 模式（建議）

```bash
bash scripts/setup.sh ansible
```

依序輸入：

1. SSH 使用者、監控主機的 inventory 名稱與 SSH 位址、遠端部署目錄。
2. Agent 能連到的監控主機內網／VPN IPv4、Grafana 網址／綁定位址／時區／帳號、資料保留時間與遠端資料目錄。
3. 是否啟用 Odoo、Nginx 插件，以及是否在監控主機本身部署 Agent。
4. 額外應用主機數量，以及每台的名稱、SSH 位址、角色、Docker 網路與允許的環境 regex。
5. 首次設定時，輸入並確認 Grafana 密碼，再設定 Vault 加密密碼。

Enter 使用畫面顯示的預設值。`[Y/n]` 預設是；`[y/N]` 預設否。密碼不會回顯，也不會列在完成摘要中。監控用 IP 目前支援 IPv4；SSH 位址可使用 IPv4 或 DNS 名稱。

輸出：

| 檔案 | 內容 |
|---|---|
| `deploy/inventory.local.yml` | 所有主機、角色及每台的部署參數 |
| `deploy/group_vars/all/vault.yml` | 新建時直接加密的 Grafana 密碼與空的選用 secrets |

個人設定全部放在 inventory 的 host vars，優先於共用的 `group_vars/all/main.yml`，不必修改版本控制中的預設值。Unix 產物權限為 `0600`，Windows 使用前述使用者 ACL；Vault 明文僅暫存於權限受限的工作目錄，加密完成或離開精靈時清除。

**若已有加密 Vault，會完整保留它，不會重設 Grafana 密碼或刪除 DB／通知 secrets。** 修改密碼請使用 `ansible-vault edit deploy/group_vars/all/vault.yml`。已有未加密的 Vault 時精靈會停止，請先加密。Grafana 密碼只在首次初始化生效，既有 Grafana 帳號須從介面或 CLI 修改。

完成後依畫面列出的指令操作：

```bash
cd deploy
ansible-galaxy collection install -r requirements.yml -p .collections
ansible all -i inventory.local.yml -m ping --ask-vault-pass
ansible-playbook -i inventory.local.yml site.yml --syntax-check --ask-vault-pass
ansible-playbook -i inventory.local.yml site.yml --ask-vault-pass
```

每次都要指定 `-i inventory.local.yml`，否則會使用原本的範例 inventory。sudo 需要密碼時加 `--ask-become-pass`。SSH key 可透過 ssh-agent 或 `--private-key` 指定。

插件清單會套用到本次設定的 Server 與各 Agent，Ansible 部署時自動產生插件內容；各主機需要不同清單時，在產出的 inventory 修改對應 `lookout_plugins`。

## 直接部署 Compose

在要部署的原始碼目錄執行：

```bash
bash scripts/setup.sh server
# 或在 Agent 主機：
bash scripts/setup.sh agent
```

Server 模式填寫監控 IP、Grafana、保留時間、資料目錄、插件與管理員密碼；Agent 模式填寫主機名稱、角色、Docker 網路、環境／容器 regex、監控 IP 與插件。分別產生 `server/.env` 或 `agent/.env`，並組合 `generated/` 設定。

Server 使用的內網 IP 也必須能從容器連線，因此同機部署仍不能填 `127.0.0.1`。Alloy 的兩個推送 URL 會根據監控 IP 自動產生。Grafana 預設只綁 localhost。

精靈最後顯示準備資料目錄、檢查 Compose 與啟動服務的指令。手動模式的插件清單會重新組合該部署目錄內的 Agent 與 Server 產物；兩者在同一份目錄時，請選取兩者所需的完整插件清單。

## 重跑與進階設定

- 遇到既有 `.env` 或 `inventory.local.yml`，預設不覆寫。確認繼續後以新輸入重建，原檔存為同目錄下的 `.backup-*`，權限同樣為 `0600`，並排除 git。
- 精靈不讀取或執行既有 `.env`；重跑時不會沿用之前的欄位值。自行加入的 DB DSN 等額外變數，請從備份保留到新設定。
- 密碼可含 `$`、反斜線、空格等文字，會以字面值寫入。為配合目前的 Ansible `.env` 範本，拒絕單引號、控制字元及 Jinja 樣板字串。
- DB 帳號／targets、通知管道與應用容器 label／log 格式仍依 [targets](targets.md)、[alerts](alerts.md)、[plugins](../plugins/README.md) 設定。
- 遠端須先安裝 Docker Engine、Compose v2、Python 3，應用 Docker 網路與資料碟掛載須已存在。精靈不會自動準備這些資源。

可指定另外的輸出根目錄，供離線準備或檢查：

```bash
bash scripts/setup.sh ansible --output-dir /tmp/lookout-config
bash scripts/setup.sh --help
```

`--output-dir` 只輸出設定，不包含 Compose、Playbook 或應用原始碼；部署前須將產物放進對應的完整 Lookout 目錄。
