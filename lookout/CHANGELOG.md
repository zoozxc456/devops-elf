# 變更紀錄

## [Unreleased]

## [1.0.0] - 2026-10-23

首個有版本號的發行，包含通用監控、插件與兩種設定精靈；先前同日開發內容統一收錄於此版。

### 版本管理

- 使用 VERSION 作為專案版本來源，採 major.minor.patch。
- 提供版本一致性檢查、major / minor / patch 更新及 dry-run，發版時將 Unreleased 移入新版本。
- 插件產物記錄來源版本；Ansible 分別記錄 Server / Agent 的部署來源版本。

### PowerShell 引導式設定

- 新增 scripts/setup.ps1，支援 PowerShell 7.2+ 的 Ansible / Server / Agent 設定精靈。
- Server / Agent 由原生 PowerShell 與本機 Python 產生；Windows 的 Vault 加密透過 WSL 的 ansible-vault，部署使用 Linux／WSL 控制端。
- 支援 SecureString 密碼輸入、UTF-8 無 BOM／LF、Unix 私密權限及 Windows 使用者 ACL、既有設定備份與 Vault 保留。
- 新增 PowerShell 模擬互動、產物、Vault 加密與 inventory 解析測試。Windows ACL 與 WSL 橋接仍需於 Windows 主機驗收。

### Bash 引導式設定

- 新增 scripts/setup.sh：互動建立 Ansible inventory / Vault 或 Server / Agent .env。
- 支援主機／網路／保留時間／插件設定、隱藏密碼確認、既有設定備份與輸入檢查。
- Ansible 模式只建立加密 Vault，既有 Vault 保留；個人設定及備份排除 git。
- 設定精靈只產生檔案與後續指令，不自動部署。新增互動流程、Compose 解析、真實 Vault 加密與 inventory 解析測試。

### 選用插件

- Odoo / Nginx 的 parser、dashboard、Nginx 告警與應用設定範例移至 plugins/。
- 核心移除專屬面板；以 scripts/plugins.py apply 的完整清單產生部署設定，預設不載入插件。
- Compose 使用 generated/ 產物；Ansible 依各主機 lookout_plugins 自動產生並同步，停用後移除對應內容。
- 所有 log stage 在單一 loki.process 中執行，保留 extracted fields 到共用的 level 正規化。
- 核心及插件設定檢查、4 組插件產生測試、Ansible 各主機清單測試，以及 Odoo / Nginx 範例 log 的實際解析驗證均通過。

### 通用自行部署版本

- 接續既有移植，以 `agent/alloy/` 的核心、共用 exporter 模組與各主機 targets 為統一結構。
- Ansible 改用一般 SSH、任意主機／環境／應用網路；移除固定 GCP、Odoo 網路與 PostgreSQL 環境清單。
- Agent、資料庫 target、Server 保留時間、Grafana 網址／時區與通知 secrets 均可自訂。
- 資料庫及通知預設不啟用；Odoo 保留為選用 parser 與儀表板。
- 告警與儀表板依 host / env / service / format 查詢，移除固定容器名稱。
- 多主機消失偵測保留每台 host；預設以 24 小時歷史判定，靜態必要主機檢查另見 docs/alerts.md。
- 修正 cAdvisor dashboard 依賴已被移除的 Compose project label，以及 Grafana 時區環境變數。
- 新增快速開始、labels、targets、Nginx、告警、維運文件與資料目錄準備工具。
- 新增 scripts/check.sh 與多主機告警案例。Playbook 不再管理磁碟格式化與掛載。

驗證：Compose 與 Alloy（含三種 DB exporter 模組）語法、15 條 Prometheus 規則、3 組告警案例、Loki / Alertmanager 設定、7 份 dashboard JSON、42 條自訂 dashboard 查詢、Ansible syntax 與本機 env 範本渲染。隔離 Server 的四個服務健康檢查、Grafana provisioning 與 Loki 寫入／查回均通過。

未執行正式遠端部署，亦未連線實際資料庫或發送通知；實際 Linux Agent 的主機權限、資料庫帳號與通知管道須於目標環境完成驗收。
