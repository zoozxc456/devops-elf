# Lookout 插件

[English](README.md) | **繁體中文**

核心只提供主機／容器監控、通用 log（raw / JSON / logfmt / PostgreSQL）、資料庫 exporter 與一般告警。Odoo、Nginx 的特有解析、儀表板與規則放在這裡，預設不載入。

| 插件 | 內容 |
|---|---|
| [odoo](odoo/README.zh-TW.md) | 多行 traceback、db/logger metadata、Odoo 儀表板 |
| [nginx](nginx/README.zh-TW.md) | access/error log 解析、Nginx 設定範例、儀表板、5xx／延遲告警 |

## 手動部署

在 lookout 根目錄執行，需要 Python 3，無額外套件：

```bash
python3 scripts/plugins.py list
python3 scripts/plugins.py apply odoo nginx  # 啟用兩個
# python3 scripts/plugins.py apply nginx    # 僅啟用 Nginx
# python3 scripts/plugins.py apply          # 只保留核心
```

`apply` 後的參數是**完整清單**，不是增量。它只產生 `agent/generated/` 與 `server/generated/`，不修改原始設定、.env、資料或 secrets。生成目錄由工具管理並排除 git，請勿在裡面編輯；再次執行會依最新來源重建，移除已停用插件的產物。名稱錯誤或重複、檔名或 dashboard UID 衝突會拒絕產生。

每個部署主機需有自己的產物：Agent 主機產生所需 parser，Server 主機啟用所有需要顯示／告警的插件。可在控制端用 `--output /tmp/lookout-build` 輸出，再把 `agent/generated/`、`server/generated/` 放到部署目錄的相同位置；不要求遠端保留完整原始碼。

首次啟動前必須執行一次 `apply`（不需要插件也要執行）。修改插件清單或原始設定後重新 apply，再套用：

```bash
cd agent
docker compose up -d --force-recreate alloy
# 在 Server 主機的 server/ 目錄：
docker compose up -d --force-recreate loki grafana
```

生成設定透過 bind mount 載入，更新後重建容器以載入新內容。插件不會修改你的應用容器；仍需依各插件文件加 label 與 log 格式。未啟用插件的 format 會丟棄 log，避免誤以為已完成解析。

## Ansible

在 group_vars 或各主機 host_vars 設定：

```yaml
lookout_plugins: [odoo, nginx]
```

預設 `[]`。角色在控制端產生各主機的設定並同步至遠端，不要求手動 apply。Agent pipeline 改動會重建 Alloy；Server 規則／儀表板同步會移除停用的插件，Loki／Grafana 自動重讀。只有第一次切換掛載路徑時會隨 Compose 變更重建服務。

## 檔案結構與擴充

```text
plugins/<名稱>/
  README.md
  README.zh-TW.md
  agent/log-stages.alloy.inc   # 插入 loki.process 的 stage 區塊，非獨立 Alloy 設定
  grafana/dashboards/*.json    # 選用，須有唯一檔名與 uid
  loki/rules/fake/*.yml        # 選用，單租戶告警規則
  config/                     # 選用，應用本身的設定範例
```

插件名稱使用小寫英文字母、數字與連字號，format label 與名稱一致。stage 應用 `stage.match` 限制在自己的 format；解析出的 level 由核心統一正規化，env 由核心再次套用 LOOKOUT_ENVS。db、logger、vhost 等高基數欄位應放 structured metadata。

所有 stage 組合在同一個 `loki.process`，讓 extracted fields 能保留到共用的 level 正規化階段。不要將片段當作獨立 Alloy component 載入。插件現階段提供 log stage、Loki 規則與 Grafana dashboard，資料庫 exporter 仍使用核心 targets 機制。

## 驗證

```bash
./scripts/check.sh             # 只有核心
./scripts/check.sh odoo nginx  # 核心加兩個插件
python3 -m unittest discover -s tests -p 'test_plugins.py'
```
