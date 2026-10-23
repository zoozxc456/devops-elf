# DevOps Elf

[English](README.md) | **繁體中文**

A little elf for everyday DevOps — a growing collection of tools, scripts, and infrastructure essentials.

日常維運的小精靈，持續收錄實用工具、自動化腳本與基礎設施元件。

目前包含 Google Cloud IAP 連線管理、Lookout（Grafana + Loki + Alloy + Prometheus 監控環境），以及含 pgBackRest 與 pgvector 的 PostgreSQL 18 映像；各專案可獨立使用，未來會持續擴充。

[變更紀錄](CHANGELOG.md) · [貢獻指南](CONTRIBUTING.md) · [安全政策](SECURITY.md) · [MIT 授權](LICENSE)

## 專案導覽

| 專案 | 用途 | 主要環境 | 版本來源 |
|---|---|---|---|
| [Google IAP Client Manager](google-iap-client-manager/README.zh-TW.md) | 管理 VM 的 IAP SSH 與 TCP tunnel，支援設定精靈、入口提示、匯出及管理連線 | Bash 3.2+ 或 PowerShell 7.2+；實際連線需 gcloud | `iap` 的 `VERSION` 與 `iap.ps1` 版本輸出 |
| [Lookout](lookout/README.zh-TW.md) | 以 Grafana + Loki + Alloy + Prometheus 組成的自架監控環境，收集與查詢 metrics / logs，搭配 Alertmanager 告警、Odoo / Nginx 選用插件及 Ansible 部署 | Linux、Docker Engine 與 Compose v2；設定工具依模式需要 Python、PowerShell 或 Ansible | [lookout/VERSION](lookout/VERSION) |
| [PostgreSQL 18 映像](postgres18-with-pgbackrest-client/README.zh-TW.md) | 在 `postgres:18` 基礎上安裝 pgBackRest、pgvector 與 CA 憑證 | 可建置及執行 Linux 容器的 Docker 環境 | 該專案 [CHANGELOG](postgres18-with-pgbackrest-client/CHANGELOG.md) 與 README 的映像版本 |

三個專案各自維護版本與設定，不需要一起安裝，也沒有根目錄的統一部署指令。IAP 可用來連線雲端主機，Lookout 可監控主機與資料庫；兩者不會自動整合或部署 PostgreSQL 映像。

## 目錄結構

```text
devops-elf/
├── README.md
├── README.zh-TW.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── SECURITY.md
├── google-iap-client-manager/       # IAP CLI、安裝器、設定與管理工具
├── lookout/                         # Server / Agent、插件、Ansible 與操作文件
└── postgres18-with-pgbackrest-client/ # Dockerfile 與資料庫映像維護文件
```

## 文件分工

所有 README 均提供英文與繁體中文版本。共用貢獻指南與安全政策使用英文，其他詳細維護指南目前保留繁體中文。更新 README 時，請同步維護兩個語言版本的專案清單、指令與連結。

| 文件 | 維護位置與用途 |
|---|---|
| README | 根目錄提供導覽；各子專案提供自己的安裝、設定與使用說明 |
| CHANGELOG | 根目錄記錄共用與跨專案變更；各子專案記錄自己的版本歷史 |
| CONTRIBUTING | 根目錄維護共用流程；[IAP 開發補充](google-iap-client-manager/CONTRIBUTING.md)、[Lookout 版本管理](lookout/docs/versioning.md) 與 [映像維護指南](postgres18-with-pgbackrest-client/GUIDELINE.md) 保留專屬規則 |
| SECURITY | 根目錄統一漏洞回報與安全政策；[IAP 安全補充](google-iap-client-manager/SECURITY.md) 說明其本機檔案與連線行為 |
| LICENSE | 根目錄 MIT 涵蓋自行撰寫的內容；IAP 保留授權副本供獨立散布 |

若將子專案抽出獨立散布，請附上適用的 LICENSE 與必要著作權聲明，並調整原本指向根目錄的文件連結。第三方內容仍適用原有授權。

## 開始使用

以下指令皆從本資料夾根目錄開始。請先取得原始碼並依各專案需求安裝相依工具。

### Google Cloud 連線管理

macOS / Linux：

```bash
cd google-iap-client-manager
bash install.sh --setup
# 依安裝畫面載入 shell 設定或開啟新終端機後：
iap ls
```

PowerShell：

```powershell
Set-Location google-iap-client-manager
pwsh -NoProfile -File ./install.ps1 -Setup
# 開啟新 PowerShell 工作階段後：
iap ls
```

安裝預設加入使用者 PATH；`--setup` / `-Setup` 會啟動設定精靈。精靈不會登入 Google Cloud 或建立連線，實際使用前需完成 gcloud 登入及 IAP／SSH 權限設定。設定檔格式、平台差異與連線指令見 [IAP README](google-iap-client-manager/README.zh-TW.md)。

### Lookout — Grafana + Loki + Alloy + Prometheus

```bash
cd lookout
bash scripts/setup.sh
```

選擇 Ansible、Server 或 Agent，產生個人設定後，依精靈列出的指令繼續部署。精靈不會自動啟動服務；實際被監控主機須為 Linux。架構、手動 Compose 部署、資料庫 targets、通知與插件見 [Lookout README](lookout/README.zh-TW.md)；多主機部署見 [Ansible 指南](lookout/deploy/README.zh-TW.md)。

### PostgreSQL 映像

```bash
cd postgres18-with-pgbackrest-client
docker build -f dockerfile -t postgres18-with-pgbackrest-client:1.1.0 .
docker run --rm postgres18-with-pgbackrest-client:1.1.0 pgbackrest version
```

這個步驟只建置映像並檢查工具版本，不會啟動資料庫。pgBackRest 設定、資料掛載與 `CREATE EXTENSION vector` 操作見 [映像 README](postgres18-with-pgbackrest-client/README.zh-TW.md)。備份排程及 repo host 需另外配置。

## 驗證與維護

各專案有不同的驗證方式，請依修改範圍執行，詳見 [CONTRIBUTING.md](CONTRIBUTING.md)。根目錄的 CHANGELOG 記錄共用文件及跨專案變更，各專案 CHANGELOG 保留其功能與發布歷史。

設定精靈、安裝、容器啟動與 Ansible 部署的影響不同；執行前請先閱讀對應指令的文件。真實設定、密碼、資料、備份與 Vault 不應提交至原始碼庫。完整回報方式與操作注意事項見 [SECURITY.md](SECURITY.md)。

## 授權

本工具集自行撰寫的程式碼與文件採用 [MIT License](LICENSE)。第三方映像、套件、儀表板與其他引用內容仍適用其各自的授權與著作權聲明。
