# Nginx 插件

[English](README.md) | **繁體中文**

先在 lookout/ 執行 `python3 scripts/plugins.py apply nginx`（其他插件也要一併列出），並依 [插件操作方式](../README.zh-TW.md) 套用。Ansible 設定 `lookout_plugins: [nginx]`。

可直接參考 [http.conf](config/http.conf) 與 [log-output.conf](config/log-output.conf)，依自己的 Nginx include 路徑與網域調整。

將 Nginx 容器加上 `lookout.enable=true`、`lookout.format=nginx`、`lookout.service=nginx` 與適當的 `lookout.env`。名稱可自訂。Alloy 讀 stdout/stderr，所以需輸出一份 JSON access log 到 `/dev/stdout`。

在 Nginx `http` 區塊（或它載入的 conf.d 檔案）加入，並在使用之前定義：

```nginx
map $host $lookout_env {
    default prod;
    staging.example.com staging;
}
log_format lookout escape=json
    '{"env":"$lookout_env",'
    '"vhost":"$host",'
    '"method":"$request_method",'
    '"uri":"$uri",'
    '"status":$status,'
    '"bytes":$body_bytes_sent,'
    '"request_time":$request_time,'
    '"upstream_status":"$upstream_status",'
    '"upstream_response_time":"$upstream_response_time"}';
```

在需要監控的 `server` 或 `location` 加入：

```nginx
access_log /dev/stdout lookout;
error_log /dev/stderr warn;
```

可保留原本寫檔的 access/error log。用 `$uri` 避免 access log 記錄 query string 的 token；Nginx 原生 error log 仍可能包含完整 request，敏感環境需另行遮罩。Alloy 會丟掉非 JSON 的 access log，不要同時把預設 main 格式送到 stdout。

```bash
# 將 nginx 換成自己的容器名稱
docker exec nginx nginx -t
docker exec nginx nginx -s reload
docker logs --tail 5 nginx
```

多環境代理的 `LOOKOUT_ENVS` 必須包含容器 env 與 map 寫入的各環境。Grafana Explore 範例：

```logql
{format="nginx", service="nginx"}
{format="nginx", env="prod"} | status=~"5.."
{format="nginx", level=~"ERROR|CRITICAL|WARN"}
```

Nginx 儀表板與告警依 `format="nginx"` 查詢，可同時使用多台代理。預設 5xx > 5% 且 5 分鐘 > 20 筆請求，或 p95 > 5 秒持續 10 分鐘才告警。
