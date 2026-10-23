# 維護規範

修改 `postgres18-with-pgbackrest-client` image 時請依照本文件的規範進行。共用貢獻與安全規範分別見根目錄 [CONTRIBUTING.md](../CONTRIBUTING.md) 與 [SECURITY.md](../SECURITY.md)。

## 版本規則

image 版本遵循 [Semantic Versioning](https://semver.org/lang/zh-TW/)（`MAJOR.MINOR.PATCH`）。判斷基準是**既有的 container、資料目錄和 pgBackRest 備份，換成新 image 後能不能直接使用**。

| 類型 | 何時使用 | 範例 |
| --- | --- | --- |
| MAJOR | 換成新 image 後，舊的資料目錄或備份無法直接使用，或需要人工遷移 | 升級 PostgreSQL 大版本（18 → 19）、改變資料目錄或 pgBackRest 目錄路徑、移除已安裝的 extension |
| MINOR | 向下相容的功能新增 | 新增 extension 或套件（例如 1.1.0 加入 pgvector） |
| PATCH | 不影響功能的修正 | 重新 build 取得安全性更新、修正權限、文件修正 |

注意事項：

- **移除 extension 一律算 MAJOR**。已經 `CREATE EXTENSION` 的資料庫換到沒有該 extension 的 image 會無法使用，pgBackRest 還原也一樣。
- 基底 `postgres:18` 的 minor 版本更新（例如 18.0 → 18.1）視為 PATCH。

## 修改流程

1. **修改 `dockerfile`**
   - 新套件加在現有的 `apt-get install` 清單中，維持單一 `RUN` layer，並保留結尾的 `rm -rf /var/lib/apt/lists/*`。
   - 套件一律加上 `--no-install-recommends`。
   - PostgreSQL extension 使用 PGDG 套件，名稱格式為 `postgresql-18-<name>`，不要從原始碼編譯（除非 apt 沒有提供需要的版本）。
   - 套件清單照用途分組：pgBackRest 相關、PostgreSQL extension、系統工具。
2. **Build 並驗證**（見下一節）。
3. **更新 `CHANGELOG.md`**
   - 在 `[Unreleased]` 下記錄變更，發佈時改為 `## [x.y.z] - YYYY-MM-DD`。
   - 使用 `Added` / `Changed` / `Deprecated` / `Removed` / `Fixed` / `Security` 分類。
   - 如果升級需要額外操作，或會影響備份還原，加上「升級注意事項」段落。
4. **更新 `README.md`**：調整「目前版本」、「內容物」表格，以及範例中的 image tag。
5. **打 tag 並 push image**：同時推送 `x.y.z` 與 `x.y` 兩個 tag，不要只依賴 `latest`。

## 驗證清單

發佈前至少確認以下項目：

```bash
IMAGE=postgres18-with-pgbackrest-client:x.y.z

docker build -f dockerfile -t "$IMAGE" .

# pgBackRest 可以執行
docker run --rm "$IMAGE" pgbackrest version

# extension 套件已安裝
docker run --rm "$IMAGE" dpkg -l postgresql-18-pgvector

# 目錄擁有者為 postgres
docker run --rm "$IMAGE" ls -ld /etc/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest
```

啟動 container 並確認 extension 可以建立：

```bash
docker run -d --name pg-verify -e POSTGRES_PASSWORD=verify "$IMAGE"
sleep 5
docker exec pg-verify psql -U postgres -c "CREATE EXTENSION vector; SELECT extversion FROM pg_extension WHERE extname = 'vector';"
docker rm -f pg-verify
```

如果有改動 pgBackRest 相關內容，另外在測試環境跑一次 `pgbackrest check` 和完整的備份還原。

## pgBackRest 版本一致性

pgBackRest 要求 db host 與 repo host 使用**相同版本**，版本不一致時 `pgbackrest` 會直接回報錯誤。

- 本 image 的 pgBackRest 來自 PGDG apt repo。
- 搭配使用的 `pgbackrest-agent` 也要安裝相同版本。修改任一邊的 image 後，請在兩個 container 分別執行 `pgbackrest version` 確認一致。

## 新增 extension 的判斷

符合以下條件才加入這個 image：

- 有實際的服務需要使用，不是「之後可能會用到」。
- PGDG apt repo 有提供 `postgresql-18-*` 套件。
- 最好不需要修改 `shared_preload_libraries`。如果需要（例如 `pg_cron`、`timescaledb`），要在 README 寫清楚需要的設定，並評估是否影響既有部署。

只有特定服務需要、而且安裝成本高的 extension，應該另外維護 image，不要放進這個共用 image。
