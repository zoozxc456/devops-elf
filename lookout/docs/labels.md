# 容器 label 與資料契約

| Label | 用途 | 預設 |
|---|---|---|
| `lookout.enable` | `true` 啟用容器 log 與容器 metrics 的 env 分類 | 不啟用 log |
| `lookout.env` | 環境名稱，例如 prod、staging、dev | Agent 的 HOST_ROLE |
| `lookout.service` | 穩定的服務名稱 | Compose service 名稱，其次容器名稱 |
| `lookout.format` | raw、json、logfmt、postgres（nginx、odoo 由插件提供） | raw |
| `lookout.metrics.port` | 抓取應用的 HTTP /metrics 埠號 | 不抓取 |
| `lookout.metrics.path` | 自訂 metrics 路徑 | /metrics |

`LOOKOUT_CONTAINERS` 可用完整容器名稱 regex 代替 `lookout.enable`，例如 `nginx|api-.*`；空值只收有啟用 label 的 log。這不會推斷 log 格式，請另外設定 `lookout.format`。

`LOOKOUT_ENVS` 是允許收集的環境 regex（例如 `prod|staging` 或 `.*`）；log 先依容器 env 篩選，Nginx 解析每行 env 後再篩一次。因此多環境 Nginx 的容器 env 與每行 env 都必須被允許。主機、Agent 自身及沒有 env 的容器 metrics 不受這個閘門限制。

所有容器皆收 cAdvisor metrics，只有納管或明確指定 env 的容器會帶 env。應用 HTTP metrics 只需 `lookout.metrics.port`，不需開啟 log；Alloy 與應用必須共用 `APP_NETWORK`，容器須有 Docker 可發現的 exposed port（Dockerfile EXPOSE 或 Compose expose）。HTTP metrics 目前不包含認證與 TLS，需要時自行加入 Alloy component。

每台 Agent 的 `HOST_NAME` 必須唯一；它成為 `host`，主機／cAdvisor／Alloy 的 `instance` 也使用此值。資料庫 instance 由 targets 設定。`role` 是主機的 HOST_ROLE，`env` 是應用環境，可以不同。

Log 的低基數 label 為 `host`、`env`、`service`、`container`、`format`、`level`。Odoo 的 db/logger、Nginx 的 vhost/status 放 structured metadata。不要把 request ID、user ID、URL、租戶等高基數資料加進 label。

JSON parser 接受 level/lvl/severity/@l；logfmt 使用 level。數字層級按 Pino 的 10/20/30/40/50/60 對應 TRACE/DEBUG/INFO/WARN/ERROR/CRITICAL，不適合所有框架的數字 enum；其他格式請在來源輸出文字 level 或修改 parser。raw 不抽取 level。FATAL/PANIC 等統一成 CRITICAL。

需要額外 Docker 網路、主機檔案 log、TLS 或自訂 exporter 時，可擴充 Compose 與 `alloy/targets.alloy`，範例位於 `targets.alloy.example`。

Odoo / Nginx 必須先依 [插件說明](../plugins/README.md) 啟用；只有 label 不會自動載入插件。未啟用的 format 會丟棄 log。
