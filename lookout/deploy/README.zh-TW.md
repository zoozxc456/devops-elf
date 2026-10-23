# Ansible 部署

[English](README.md) | **繁體中文**

從控制端透過一般 SSH 將目前的 `server/` 與 `agent/` 部署至 Linux Docker 主機。不依賴 GCP、特定 VPN 或特定應用。遠端需先安裝 Docker Engine、Compose v2，SSH 使用者需能 sudo。Playbook 不安裝 Docker、不建立應用網路，也不建立資料庫帳號。

## 引導式設定

安裝 `ansible-core` 後，可在 lookout 根目錄執行：

```bash
bash scripts/setup.sh ansible
```

Windows 也可在 lookout 根目錄使用 PowerShell 7.2+：

```powershell
pwsh -NoProfile -File .\scripts\setup.ps1 -Mode ansible
```

Windows 模式需 WSL 內的 ansible-vault；後續部署在 Linux／WSL 控制端執行，參考 [Windows 操作說明](../docs/setup.md)。

逐項填入 SSH、主機、Docker 網路、插件與 Grafana 設定。精靈產生 `deploy/inventory.local.yml`，初次使用時建立加密 Vault，既有加密 Vault 則完整保留。部署時請使用 `-i inventory.local.yml`。操作與備份方式見 [設定精靈](../docs/setup.md)。

## 手動設定

```bash
pipx install ansible-core
cd deploy
ansible-galaxy collection install -r requirements.yml -p .collections
# 修改 inventory.yml 的 SSH 使用者與主機，及 group_vars/all/main.yml 的監控 IP / APP_NETWORK
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
# 換上實際 Grafana 密碼（env 值不接受單引號或換行）
ansible-vault encrypt group_vars/all/vault.yml
ansible all -m ping --ask-vault-pass
ansible-playbook site.yml --syntax-check --ask-vault-pass
ansible-playbook site.yml --ask-vault-pass
```

`inventory.yml` 使用文件專用的 `192.0.2.x` 位址，必須換成自己的主機。群組 `lookout_server` 部署監控服務，`lookout_agent` 部署 Alloy；同一個主機別名可出現在兩個群組。建議獨立監控主機也加到 agent 群組，以監控它的磁碟與記憶體。

支援 `-i inventory.local.yml` 使用自己的 inventory（已 gitignore）。`--limit app-01` 部署單台；`--tags agent` / `--tags server` 選角色。前置 vault 檢查在 localhost 執行，只檢查檔頭，不顯示內容；vault 必須已加密。`--check --diff` 可預覽已有部署的修改，但首次部署尚無目錄／Compose 時不是完整試跑，不能當成功驗證。

## 各主機設定

可建立 `host_vars/app-01.yml`，例如：

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

DSN 放加密 vault，以 inventory 名稱區分：

```yaml
vault_lookout_agent_env:
  app-01:
    PG_DSN_MAIN: postgresql://monitoring:URL_ENCODED_PASSWORD@postgres:5432/postgres?sslmode=disable
```

`lookout_agent_env` 可放不敏感的額外變數；vault 中同名值優先。額外變數不能覆蓋核心 HOST_NAME / APP_NETWORK / 推送 URL。DSN、targets 均為選用，不再預設連任何資料庫。

## Server 設定

可在監控主機 host_vars 覆寫：

```yaml
lookout_data_dir: /mnt/monitoring  # 磁碟須事先掛好；角色僅建立目錄與權限
# 若要從外部連 Grafana，建議仍綁 localhost，再配 HTTPS reverse proxy
grafana_bind_addr: 127.0.0.1
grafana_root_url: https://grafana.example.com
grafana_timezone: browser
prometheus_retention: 30d
loki_retention: 720h
loki_retention_nonprod: 168h
```

通知預設關閉。複製 `server/alertmanager/alertmanager.yml` 為自用設定檔，取消所需管道註解，透過 `lookout_alertmanager_config` 指定該檔案（控制端絕對路徑）。Secret 放 vault：

```yaml
vault_alertmanager_secrets:
  discord_webhook_url: https://discord.com/api/webhooks/REPLACE/REPLACE
```

每個 key 對應遠端 `server/secrets/` 檔案。移除某個通知管道後請自行刪除遠端已不用的 secret。自用設定檔只引用 secret 路徑，不要直接寫 token。

## 生效方式

| 變更 | 行為 |
|---|---|
| Prometheus 設定／規則 | SIGHUP reload |
| Loki 規則／Grafana dashboards | 自動重讀 |
| Grafana provisioning | 重建 Grafana |
| Loki／Alertmanager 設定、通知 secret | 重建對應容器 |
| Alloy 核心／模組／targets | 重建 Alloy |
| Compose／.env | compose up 重建受影響的服務 |

同步 server 規則與 dashboard 目錄時，也會刪除遠端已不在來源的檔案；自訂內容請保存在部署來源。部署的是本機目前檔案，請先完成 review 與 [驗證](../README.zh-TW.md)。一般 SSH 的跳板／VPN／GCP IAP 都可自行透過 inventory 的 `ansible_ssh_common_args` 設定。

## 選用插件

在各主機 host_vars 設 `lookout_plugins: [odoo, nginx]`，預設為 `[]`。Agent 與 Server 可有不同清單；Server 啟用需要的儀表板／告警，Agent 啟用實際使用的 parser。Ansible 會在控制端執行 Python 3 產生設定，不需要手動 apply。完整結構見 [plugins](../plugins/README.zh-TW.md)。

## 部署版本

角色會將來源 VERSION 複製到遠端 `{{ lookout_root }}/server/VERSION` 或 `{{ lookout_root }}/agent/VERSION`；兩者分開記錄，以便辨識局部更新。版本規則與發版流程見 [版本管理](../docs/versioning.md)。
