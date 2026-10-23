# postgres18-with-pgbackrest-client

[English](README.md) | **繁體中文**

以官方 `postgres:18` 為基底的 PostgreSQL image，額外內建：

- **pgBackRest**：讓這個 container 作為 pgBackRest 的 db host，負責 `archive_command` 與備份。
- **pgvector**（1.1.0 起）：提供 `vector` extension，用於向量儲存與相似度搜尋。

目前版本：**1.1.0**。完整變更請見 [CHANGELOG.md](CHANGELOG.md)，維護規範請見 [GUIDELINE.md](GUIDELINE.md)。

[共用貢獻指南](../CONTRIBUTING.md) · [安全政策](../SECURITY.md) · [MIT 授權](../LICENSE)

## 目錄結構

```
postgres18-with-pgbackrest-client/
├── dockerfile
├── .dockerignore
├── README.md
├── README.zh-TW.md
├── CHANGELOG.md
└── GUIDELINE.md
```

## 內容物

| 項目 | 來源 | 加入版本 |
| --- | --- | --- |
| PostgreSQL 18 | `postgres:18` 官方 image | 1.0.0 |
| `pgbackrest` | PGDG apt repo | 1.0.0 |
| `ca-certificates` | Debian apt | 1.0.0 |
| `postgresql-18-pgvector` | PGDG apt repo | 1.1.0 |

預先建立的目錄（擁有者為 `postgres:postgres`）：

| 路徑 | 用途 |
| --- | --- |
| `/etc/pgbackrest` | `pgbackrest.conf` 設定檔 |
| `/var/log/pgbackrest` | pgBackRest log |
| `/var/spool/pgbackrest` | 非同步 archive（`archive-async=y`）的 spool |

## Build

```bash
cd postgres18-with-pgbackrest-client

docker build -f dockerfile -t postgres18-with-pgbackrest-client:1.1.0 .
```

驗證安裝結果：

```bash
docker run --rm postgres18-with-pgbackrest-client:1.1.0 pgbackrest version
docker run --rm postgres18-with-pgbackrest-client:1.1.0 dpkg -l postgresql-18-pgvector
```

## 使用方式

### docker-compose 範例

```yaml
services:
  postgres:
    image: postgres18-with-pgbackrest-client:1.1.0
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    command:
      - postgres
      - -c
      - archive_mode=on
      - -c
      - archive_command=pgbackrest --stanza=main archive-push %p
    volumes:
      - pgdata:/var/lib/postgresql
      - ./pgbackrest/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf:ro
      - pgbackrest-log:/var/log/pgbackrest
      - pgbackrest-spool:/var/spool/pgbackrest

volumes:
  pgdata:
  pgbackrest-log:
  pgbackrest-spool:
```

> PostgreSQL 18 官方 image 的資料目錄改成 `/var/lib/postgresql/18/docker`，volume 要掛在 `/var/lib/postgresql`，不是舊版的 `/var/lib/postgresql/data`。

`stanza` 名稱、repo 位置等設定依你的 `pgbackrest.conf` 而定。備份排程由另外的 `pgbackrest-agent` container 負責。

### 啟用 pgvector

image 只有安裝 extension 檔案，需要的資料庫要自己啟用（每個資料庫各執行一次）：

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

如果想在第一次初始化時自動啟用，可以掛一個 SQL 檔到 `/docker-entrypoint-initdb.d/`：

```sql
-- initdb/01-pgvector.sql
CREATE EXTENSION IF NOT EXISTS vector;
```

```yaml
    volumes:
      - ./initdb:/docker-entrypoint-initdb.d:ro
```

> `docker-entrypoint-initdb.d` 只會在資料目錄是空的時候執行，而且只套用在 `POSTGRES_DB`。已經在運作的資料庫請手動執行 `CREATE EXTENSION`。

快速確認：

```sql
SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';

CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');
SELECT id FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 1;
```

## 從 1.0.0 升級到 1.1.0

1. Build 或 pull `1.1.0` 的 image。
2. 修改 compose 裡的 image tag，然後執行 `docker compose up -d postgres`。
3. 在需要的資料庫執行 `CREATE EXTENSION IF NOT EXISTS vector;`。

不需要遷移資料。注意：資料庫一旦用了 `vector`，之後的 pgBackRest 還原目標也必須是 1.1.0 以上的 image。

## 維護與授權

共用規範見根目錄 [CONTRIBUTING.md](../CONTRIBUTING.md) 與 [SECURITY.md](../SECURITY.md)，映像專屬的測試、相容性與發布規則見 [GUIDELINE.md](GUIDELINE.md)。本專案自行撰寫的內容採 [MIT License](../LICENSE)；PostgreSQL、pgBackRest、pgvector、基底映像與相依套件仍依各自授權。
