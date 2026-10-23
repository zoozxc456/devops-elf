# 變更紀錄

本檔記錄整個 `devops` 工具集的共用文件與跨專案變更。各子專案獨立維護版本，不以根目錄文件的更新推定子專案已發布新版。

## [Unreleased]

### Added

- 所有子專案、部署與插件 README 新增 `README.zh-TW.md`，保留繁中內容並提供語言切換。

- `README.zh-TW.md`：保留繁體中文首頁，提供與英文首頁互相切換的連結。

- 根目錄 `README.md`：三個專案的用途、環境需求、目錄導覽與開始使用方式。
- 根目錄 `CONTRIBUTING.md`：跨專案修改原則、驗證入口與版本管理規則。
- 根目錄 `SECURITY.md`：漏洞回報、敏感設定、監控存取與資料庫備份注意事項。
- 根目錄 MIT `LICENSE`，涵蓋本工具集自行撰寫的程式碼與文件，第三方內容保留各自授權。
- 根目錄 `CHANGELOG.md`：區分共用變更與各子專案發布紀錄。

### Changed

- 所有 `README.md` 改以英文為主，繁中 README 之間的導覽連結指向對應繁中版本。

- 根目錄 `README.md` 改為 DevOps Elf 英文首頁；詳細操作與維護文件維持繁體中文。

- 共用貢獻與安全政策集中於根目錄，IAP 文件精簡為開發與安全補充。
- 三個子專案 README 補齊共用文件入口；根目錄新增文件分工說明。
- 各專案驗證流程改由專屬文件維護；IAP 在共同版本庫中使用 `iap-vX.Y.Z` 標籤。
- PostgreSQL 映像建置範例明確使用 `-f dockerfile`，配合實際檔名。

## 各專案版本紀錄

| 專案 | 紀錄位置 |
|---|---|
| Google IAP Client Manager | [CHANGELOG.md](google-iap-client-manager/CHANGELOG.md) |
| Lookout | [CHANGELOG.md](lookout/CHANGELOG.md) |
| PostgreSQL 18 映像 | [CHANGELOG.md](postgres18-with-pgbackrest-client/CHANGELOG.md) |

既有子專案歷史保留在原位置，不重新標記為工具集的發布版本。
