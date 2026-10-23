# Lookout

[English](README.md) | **繁體中文**

[目前版本](VERSION) · [變更紀錄](CHANGELOG.md) · [版本管理](docs/versioning.md) · [共用貢獻指南](../CONTRIBUTING.md) · [安全政策](../SECURITY.md) · [MIT 授權](../LICENSE)

可自行架設的 Linux Docker 監控環境：Grafana + Loki + Prometheus + Alertmanager，使用 Grafana Alloy 收集主機、容器、應用程式與資料庫的 metrics / logs。可部署於自己的機房、任意雲端 VM 或 VPN 網路，不依賴特定公司、容器名稱或雲端帳號。

```text
Docker 主機（可多台）                   監控主機
Alloy ── logs push ──────────────────→ Loki ──┐
  ├ 主機 / cAdvisor                         ├→ Alertmanager → 自選通知管道
  ├ 容器 stdout / stderr              Prometheus ─┘
  └ 選用 DB exporter ── remote_write ─→   ↑
                                     Grafana 查詢兩者
```

## 快速開始

需求：Linux、Docker Engine（rootful）與 Compose v2。Agent 使用 cgroup、主機檔案系統與 Docker socket；macOS / Windows Docker Desktop 不作為正式主機監控環境。Server 與 Agent 可放同一台或分開。

### 引導式設定（建議 IT 使用）

在 lookout 根目錄執行，依畫面填入主機 IP、Docker 網路、插件與密碼：

```bash
bash scripts/setup.sh          # 選擇 Ansible / Server / Agent
# bash scripts/setup.sh ansible
# bash scripts/setup.sh server
# bash scripts/setup.sh agent
```

Windows 使用 PowerShell 7.2+：

```powershell
pwsh -NoProfile -File .\scripts\setup.ps1
```

Server / Agent 模式使用本機 Python 3；Windows 的 Ansible 模式需預設 WSL 發行版中的 ansible-vault。目標監控主機仍為 Linux。

Ansible 模式會產生個人的 inventory 與加密 Vault；Server / Agent 模式產生 `.env` 與插件設定。密碼隱藏輸入，完成後顯示部署指令，不會自動啟動服務。完整操作見 [設定精靈](docs/setup.md)。

下方為手動 Compose 設定步驟；使用精靈完成後，依其最後顯示的指令繼續即可。

### 0. 選擇插件

在 lookout 根目錄執行一次（需要 Python 3）：

```bash
python3 scripts/plugins.py apply             # 只有核心
# python3 scripts/plugins.py apply odoo nginx # 完整啟用清單
```

Odoo、Nginx 的解析、儀表板與告警放在 [plugins/](plugins/README.zh-TW.md)，預設不載入。每個部署目錄都須先產生設定；Ansible 會自動處理。

### 1. 監控主機

```bash
cd lookout/server
cp .env.example .env
# 編輯 .env：設定 GRAFANA_ADMIN_PASSWORD、BIND_ADDR
# BIND_ADDR 為 agent 可連線的內網或 VPN IP，例如 10.0.0.10
# 即使 server / agent 同主機，也須用容器可連線的主機 IP，不能用 127.0.0.1
sudo ../scripts/prepare-data.sh
# 檢查設定後啟動
docker compose config --quiet
docker compose up -d
```

預設資料存於 `server/data/`。指定其他位置時，在 `.env` 設 `LOOKOUT_DATA_DIR`，並以相同路徑執行 `sudo ../scripts/prepare-data.sh /mnt/monitoring`。腳本只建立目錄與權限，不處理磁碟格式化或掛載。

Grafana 預設僅綁 `127.0.0.1:3000`，可用 `ssh -L 3000:127.0.0.1:3000 user@monitoring-host` 後開啟 <http://localhost:3000>。若使用 HTTPS reverse proxy，設定 `GRAFANA_ROOT_URL` 為實際網址。

Loki 的 3100 與 Prometheus 的 9090 為無驗證的寫入／查詢 API，請只開放給可信任的內網／VPN Agent；不要直接暴露到公網。跨網段請自行配置 VPN 或帶驗證的 TLS proxy。

### 2. 每台被監控主機

```bash
cd lookout/agent
cp .env.example .env
# 編輯 HOST_NAME（全域唯一）、HOST_ROLE、LOOKOUT_ENVS、APP_NETWORK 與兩個推送 URL
# 使用現有應用網路，或先建立：
docker network create app  # 僅尚未存在時執行
docker compose config --quiet
docker compose up -d
```

主機／容器 metrics 自動開始收集；容器 log 預設須加 `lookout.enable=true`。例如在自己的 Compose service 下加入：

```yaml
services:
  api:
    image: your-api:your-version
    labels:
      lookout.enable: "true"
      lookout.env: prod
      lookout.service: api
      lookout.format: json
```

重建應用容器後 label 才會生效。沒有 label 的舊容器也可暫時用 `LOOKOUT_CONTAINERS` 的名稱 regex 納管，詳見 [labels](docs/labels.md)。

### 3. 選用資料庫與通知

- 資料庫：依 [targets](docs/targets.md) 設定 PostgreSQL、MySQL、Redis；預設不啟用任何資料庫連線。
- 通知：預設 Alertmanager 的 receiver 不對外發送。依 [alerts](docs/alerts.md) 啟用 Discord、Slack、Telegram、Teams、Email 或 webhook。
- Nginx：依 [Nginx 插件](plugins/nginx/README.zh-TW.md) 輸出安全的 JSON access log。
- 多台部署：使用 [Ansible](deploy/README.zh-TW.md)，一般 SSH 即可。

## 儀表板與告警

Grafana 的 Lookout 資料夾預設包含總覽、通用應用 log 與主機／容器／PostgreSQL 儀表板；啟用插件才會加入 Nginx 或 Odoo 專屬面板。自訂面板以 `host`、`env`、`service`、`format` 查詢，不要求固定容器名稱。

預設只針對 `env="prod"` 的應用／資料庫與 `role="prod"` 的主機告警；其他環境照樣可在 Grafana 查詢。告警門檻、消失偵測的 24 小時限制及停用主機的處理方式見 [alerts](docs/alerts.md)。Loki prod log 保留 30 天、其他 env 7 天；Prometheus 全部保留 30 天，皆可調整 `.env`。

## 驗證與操作

```bash
# 需本機 Docker、Compose v2、Python 3，會執行暫時的驗證容器
./scripts/check.sh
./scripts/check.sh odoo nginx  # 包含插件
```

啟動後檢查 Agent 的 `http://127.0.0.1:12345/-/ready` 與 Server 的 Prometheus `/-/ready`、Loki `/ready`、Grafana `/api/health`。完整流程與更新／備份見 [rollout](docs/rollout.md)。

所有個人 `.env`、資料、憑證、Agent targets 與未加密的 vault 已由 `.gitignore` 排除。來源專案留在原位置，本目錄為獨立整理後的通用版本。

## 維護與授權

共用規範見根目錄 [CONTRIBUTING.md](../CONTRIBUTING.md) 與 [SECURITY.md](../SECURITY.md)，Lookout 專屬版本與驗證流程見 [版本管理](docs/versioning.md)。本專案自行撰寫的內容採 [MIT License](../LICENSE)；第三方映像、套件與儀表板保留各自授權。
