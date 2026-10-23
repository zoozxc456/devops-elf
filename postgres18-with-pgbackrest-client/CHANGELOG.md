# Changelog

本檔記錄 `postgres18-with-pgbackrest-client` image 的所有重要變更。

格式參考 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)，版本號遵循 [Semantic Versioning](https://semver.org/lang/zh-TW/)（規則見 [GUIDELINE.md](GUIDELINE.md)）。

## [Unreleased]

## [1.1.0] - 2026-10-05

### Added

- 安裝 `postgresql-18-pgvector`（來源為官方 image 內建的 PGDG apt repo），提供 `vector` extension。
  - 只有安裝 extension 檔案，**不會**自動在任何資料庫啟用。需要的資料庫請自行執行 `CREATE EXTENSION IF NOT EXISTS vector;`。

### 升級注意事項

- 從 1.0.0 換成 1.1.0 不需要遷移資料，直接替換 image 並重啟 container 即可。
- 用到 `vector` 型別的資料庫，之後只能還原到 **1.1.0 以上**的 image。pgBackRest 還原後，如果目標 image 沒有 pgvector，PostgreSQL 會因為找不到 extension 檔案而無法使用該資料庫。

## [1.0.0] - 2026-08-07

### Added

- 以官方 `postgres:18` 為基底的初始版本。
- 安裝 `pgbackrest`，讓 PostgreSQL container 可以作為 pgBackRest 的 client（db host），搭配 `pgbackrest-agent` 執行備份與 WAL 封存。
- 安裝 `ca-certificates` 並執行 `update-ca-certificates`，供 pgBackRest 以 TLS 連線至 repo（例如 S3 相容儲存）。
- 建立 pgBackRest 所需目錄，擁有者為 `postgres:postgres`：
  - `/etc/pgbackrest`：設定檔
  - `/var/log/pgbackrest`：log
  - `/var/spool/pgbackrest`：非同步 archive 的 spool

[Unreleased]: #unreleased
[1.1.0]: #110---2026-10-05
[1.0.0]: #100---2026-08-07
