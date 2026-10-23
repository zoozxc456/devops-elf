# Odoo 插件

[English](README.md) | **繁體中文**

提供 Odoo 原生 log 的多行 traceback 合併、level/db/logger 解析與專用儀表板。db/logger 使用 Loki structured metadata，level 由核心統一為 TRACE / DEBUG / INFO / WARN / ERROR / CRITICAL。

## 啟用

```bash
# 在 lookout/ 根目錄；如需保留其他插件，請一併列出。
python3 scripts/plugins.py apply odoo
```

部署後依 [插件操作方式](../README.zh-TW.md) 重建 Alloy、Loki、Grafana。Ansible 則設定 `lookout_plugins: [odoo]`，Server 與需要解析 Odoo 的 Agent 都應啟用。

在自己的 Odoo Compose service 加入（service 與容器名稱可自訂）：

```yaml
services:
  odoo:
    labels:
      lookout.enable: "true"
      lookout.env: prod
      lookout.service: odoo
      lookout.format: odoo
```

重建 Odoo 容器後 label 才生效。LOOKOUT_ENVS 須允許對應 env。使用 Odoo 預設文字 log 格式：

```text
2026-10-23 05:12:33,123 7 ERROR mydb odoo.http: message
```

如果應用改為 JSON，可使用核心 `lookout.format=json`；此插件的 Odoo 特有欄位與儀表板則需依格式調整。

## 查詢與告警

Grafana 的 Lookout 資料夾會新增「Odoo log 總覽」，可按 env / host / service / db 篩選。

```logql
{format="odoo", env="prod"}
{format="odoo", level=~"ERROR|CRITICAL"} | db="mydb"
```

錯誤爆量沿用核心 AppErrorLogBurst 告警，不重複新增規則。Odoo 的 PostgreSQL metrics 與 log 仍由核心 PostgreSQL 支援，依 [資料來源設定](../../docs/targets.md) 另行啟用，無須固定資料庫容器名稱。
