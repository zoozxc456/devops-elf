# 告警與通知

Prometheus 規則在 `server/prometheus/rules/`，Loki 規則在 `server/loki/rules/fake/`（單租戶 ID 固定為 fake）。預設只對 prod 告警：主機用 `role="prod"`，應用／容器／資料庫與 log 用 `env="prod"`。需要其他環境時請修改規則中的 selector。

預設檢查主機 CPU／記憶體／磁碟、受監控容器停止／重啟、HTTP exporter、PostgreSQL／MySQL／Redis、錯誤 log 爆量、Nginx 5xx／延遲（需啟用 Nginx 插件）與監控元件。DB / Nginx 沒啟用時不會憑空產生故障告警。raw log 沒有 level 時不會產生錯誤爆量告警。

## 消失偵測的邊界

Agent、應用 target 與容器消失偵測，以過去 **24 小時曾出現的每台 host / instance / container** 為基準，避免一台正常掩蓋另一台故障。從未成功回報的 Agent／target 不會被這類規則發現；持續消失超過 24 小時後這類告警會消失。正式環境應另加靜態期望清單，例如每台必要主機都加：

```yaml
- alert: RequiredAgentMissing
  expr: absent_over_time(up{job="alloy", host="app-01"}[5m])
  labels:
    severity: critical
    host: app-01
    env: prod
  annotations:
    summary: app-01 五分鐘沒有 Agent 資料
```

靜態規則可涵蓋從未上線與長期故障。淘汰主機或 rename 容器時，移除自訂規則並在 Alertmanager silence 舊 host / name 24 小時，避免歷史偵測持續通知。容器重建改名會視為不同容器。

未輸出 log 不一定是故障，預設不檢查 log 中斷。有固定 heartbeat 的服務可自行加入指定 host/service 的 `absent_over_time` 規則。監控主機整台故障或網路全面中斷時，自架告警也可能無法送出；需要時從外部監控監控主機。

## 啟用通知

預設 receiver 不對外發送，先確認資料與告警門檻再啟用。在 `server/alertmanager/alertmanager.yml` 取消所需管道的註解（Discord／Slack／Telegram／Teams／Email／webhook），可同時開多種。Webhook / token 使用 `*_file` 放 `server/secrets/<檔名>`，檔案不進 git。

例如 Discord：建立 `server/secrets/discord_webhook_url`，內容為自己的 webhook URL；取消 discord_configs 區塊註解，然後：

```bash
cd server
sudo chown 65534:65534 secrets/discord_webhook_url
sudo chmod 400 secrets/discord_webhook_url
docker compose up -d --force-recreate alertmanager
```

其他管道依範例填寫 channel、chat_id 或 SMTP。通知使用 Alertmanager 內建樣板，可依需求自訂。Ansible 使用 `lookout_alertmanager_config` 與 `vault_alertmanager_secrets`，見部署文件。

改完 Prometheus 規則可 `docker kill --signal=HUP lookout-prometheus`；Loki 每分鐘重讀規則。更改 Alertmanager 或 Loki 單檔 bind mount 設定後需重建對應容器；單純 restart 可能仍讀舊 inode。

驗證請執行 `scripts/check.sh`，再於 Prometheus `/alerts` 及 Alertmanager API 確認告警狀態；啟用通知後應實際測試 firing 與 resolved。

Nginx 規則來源已移到 [Nginx 插件](../plugins/nginx/README.md)，部署使用 `server/generated/loki-rules/`；核心 `server/loki/rules/` 不包含插件規則。請編輯來源後重新 apply，不要直接編輯生成目錄。
