# 部署、更新與維護

1. 選擇可被 Agent 存取的監控主機內網／VPN IP，確認 Docker Engine 與 Compose v2 已安裝。跨主機開通僅必要來源到 3100／9090。
2. 準備資料目錄（建議獨立資料碟，磁碟由自己事先掛載），依 README 執行 `scripts/prepare-data.sh`；準備 Server `.env`，設定密碼與綁定 IP。
3. 啟動 Server，確認 Prometheus `/-/ready`、Loki `/ready`、Grafana `/api/health`；Grafana 使用 SSH tunnel 或 HTTPS proxy。
4. 選一台 Agent，設定唯一 HOST_NAME、APP_NETWORK、HOST_ROLE、LOOKOUT_ENVS 與推送 URL。確認 Docker socket、containerd socket 與 `/var/lib/docker` 路徑符合主機；自訂 Docker data-root 時需對應修改 bind mount。Agent 需要 privileged 與主機目錄，應部署在可信任且由你管理的 Linux Docker 主機。
5. 先收一個有 label 的服務，確認 Grafana Explore `{host="app-01"}` 有 log，Prometheus `up{job="alloy",host="app-01"}` 為 1，`node_uname_info` 與 `container_last_seen` 有資料。
6. 依需求啟用資料庫、Nginx 與應用 HTTP metrics；使用 PostgreSQL 等對應的 up 指標確認 exporter 能連到資料庫，不能只看 Alloy readiness。
7. 觀察告警門檻並設定通知，測試停止測試用服務是否出現 firing / resolved。分批將其他 Agent 加入；更動允許環境時同步調整 LOOKOUT_ENVS。

## 更新

先備份資料與 `.env`／secrets，執行 `scripts/check.sh`，再對照映像 release notes 更新。修改 `.env` 或 Compose 用 `docker compose up -d`；Alloy 的設定目錄修改後需 `docker compose restart alloy`（Ansible 會重建）。Grafana 儀表板自動重讀；provisioning 需重建 Grafana。單檔掛載的 Loki / Alertmanager 設定需 `--force-recreate`。

`docker compose down` 停服務，主機上的資料目錄會保留。不要刪除資料目錄或 Agent 的 alloy-data volume，除非刻意要清除歷史／讀取位置。Grafana 密碼只在首次初始化生效，之後用介面或 Grafana CLI 修改。

## 備份

備份 Server 的四個資料目錄，以及 `.env`、Alertmanager secrets、自己維護的規則／dashboard 與 Agent targets。使用服務一致性快照或停機備份；不能只備份這個程式目錄的範例。監控日誌可能含敏感業務資料，備份的存取權限應與原資料一致。

## 故障檢查

- Agent ready 但查不到資料：檢查 `docker compose logs alloy` 的 remote_write / Loki 錯誤、server 綁定 IP、網路 ACL 與 URL。容器內的 127.0.0.1 是容器自己。
- 沒有 log：確認 label 已加在實際容器、stdout/stderr 有輸出、LOOKOUT_ENVS 放行且 format 正確。
- 沒有 DB metrics：targets 預設皆註解；確認 DSN、DNS、APP_NETWORK、監控帳號權限。
- 沒有通知：預設 receiver 為空，需啟用管道與 secret，檢查 Alertmanager log。
- permission denied：確認 prepare-data 的 UID/GID 與實際映像匹配；rootless、userns-remap、SELinux 主機需自行調整權限／掛載政策。

修改核心 log pipeline、dashboard 或插件來源後，手動部署須先依 [插件說明](../plugins/README.md) 重新執行 apply（列出完整插件清單），再重建對應容器。生成檔案不需要備份，原始設定、插件清單與個人 targets/.env 需要保留。Ansible 會自動組合與同步。

正式更新前確認 [版本管理](versioning.md) 中的 VERSION 與 CHANGELOG 一致，依該版記錄完成必要遷移。Ansible 部署後可查看各角色的 VERSION 檔案。
