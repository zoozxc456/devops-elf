# 資料庫與檔案來源（選用）

主機／容器監控不需要資料庫。需要時：

```bash
cd agent
cp alloy/targets.alloy.example alloy/targets.alloy
# 只取消實際要啟用的區塊註解；連線字串放 .env
# 設定後驗證並重啟
docker compose run --rm --no-deps alloy validate /etc/alloy
docker compose restart alloy
```

修改 `.env` 後必須用 `docker compose up -d` 重建；單純 restart 不會重新載入環境變數。相同模組可使用不同的 block 名稱建立多個實例。`env` 必須通過 LOOKOUT_ENVS，`instance` 建議使用易識別的唯一名稱。資料庫須能從 Alloy 的網路到達；可以是遠端主機，不限定容器。

## PostgreSQL

用資料庫管理員建立專用監控帳號。透過 psql 互動輸入密碼，避免密碼進 shell history：

```sql
CREATE ROLE monitoring LOGIN;
\password monitoring
GRANT pg_monitor TO monitoring;
GRANT CONNECT ON DATABASE postgres TO monitoring;
```

確認 pg_hba.conf 允許 Agent 來源。`.env` 加入：

```dotenv
PG_DSN_MAIN='postgresql://monitoring:URL_ENCODED_PASSWORD@postgres:5432/postgres?sslmode=disable'
```

`sslmode=disable` 僅用於可信任的容器網路；遠端連線依資料庫 TLS 設定調整。密碼中保留字須 URL encode，例如 `@` → `%40`、`/` → `%2F`。不要使用管理員帳號當 exporter 帳號。

## MySQL

以下為 MySQL 8 的監控帳號範例，來源 host 請限縮成 Agent 所在網段，並換上獨立密碼：

```sql
CREATE USER 'monitoring'@'10.0.0.%' IDENTIFIED BY 'REPLACE_WITH_PASSWORD' WITH MAX_USER_CONNECTIONS 3;
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'monitoring'@'10.0.0.%';
```

```dotenv
MYSQL_DSN_MAIN='monitoring:PASSWORD@(mysql:3306)/'
```

MySQL DSN 是 exporter 的 Go driver 格式，並非 URL，不要套用 PostgreSQL 的 URL encode 規則。特殊密碼字元請依 driver 格式處理；MariaDB 或其他版本請依實際 collector 的權限需求調整。

## Redis

```dotenv
REDIS_ADDR_CACHE='redis://redis:6379'
# 有密碼或 ACL 時依 Redis exporter 支援的 URI 格式加入認證，例如 redis://user:URL_ENCODED_PASSWORD@redis:6379
```

Redis ACL 所需命令依 collector 而異，請使用專用監控帳號，參照 [redis_exporter](https://github.com/oliver006/redis_exporter#redis-acl)。本專案不自動更改資料庫使用者或權限。

## 主機檔案 log

`targets.alloy.example` 底部包含 local.file_match / loki.source.file 範例。先把來源目錄唯讀掛進 Agent，再取消範例註解並設定 env/service/format。範例從檔尾開始讀，不回補舊資料；Alloy state volume 保存讀取位置。
