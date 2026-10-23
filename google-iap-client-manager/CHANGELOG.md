# Changelog

版本號採 [SemVer](https://semver.org/lang/zh-TW/)：`主版號.次版號.修訂號`。
尚未發布的變更列於 `Unreleased`；保留既有版本紀錄與日期。發布時須同步 Bash 與 PowerShell 版號，流程見 [貢獻指南](CONTRIBUTING.md)。

## [Unreleased]


### Added
- 完整的專案使用文件、`CONTRIBUTING.md` 貢獻指南、`SECURITY.md` 安全政策與 MIT `LICENSE`
- `iap export [FILE]`：Bash / PowerShell 匯出目前設定，支援指定輸出、原始格式保留、私有權限與覆寫前確認／備份
- `iap help` 與 `--help` / `-h` 顯示相同說明，並加入補全與保留名稱
- `iap remove <name>`、`iap edit <name>`、`iap reset`、`iap uninstall`，Bash 與 PowerShell 同步支援
- 管理操作包含影響範圍確認、私有備份、編輯驗證與設定變更偵測；解除安裝保留使用者設定與另一個 shell 版本
- `iap new`（Bash / PowerShell）：互動新增單一 SSH / tunnel，保留既有連線與設定，含重名檢查、備份與取消保護

### Changed
- install 預設持久加入 PATH：Bash / zsh 寫入 shell 設定；Windows PowerShell 更新使用者 PATH，Unix PowerShell 寫入 profile，避免重複並保留既有設定
- 提供 `--no-path` / `-NoPath` 與自訂 profile 選項；update 只更新程式，不修改 PATH
- 安裝完成顯示實際安裝版本；更新完成顯示更新前後版號（Bash / PowerShell）
- setup 既有設定提示明確說明整份重建，建議使用 new / edit，並偵測輸入期間的設定變更
- Tunnel 入口提示在啟動時顯示並註明連線建立後可用，不必等待 gcloud 的 Listening 訊息
- Bash / PowerShell 安裝改為直接複製 `iap` / `iap.ps1` 到 local bin，不再建立連結或原始碼轉接腳本
- setup、共用函式與補全同步複製到 bin 下的 `.iap/`，刪除原始碼後仍可使用
- 支援重複安裝與舊版安裝遷移；`iap update` 依安裝來源更新 Git 或同步本機目錄，並自動更新 bin 中的副本與配套檔案

## [0.4.1] - 2026-10-23

### Added
- PowerShell 7.2+ 的 `install.ps1`、`scripts/setup.ps1`、原生 `iap.ps1` 與 Tab 補全
- PowerShell 設定精靈共用 Bash 設定格式，支援多連線、驗證、備份與 UTF-8 無 BOM / LF 輸出
- Windows 設定檔與備份使用僅目前使用者可存取的 ACL；Unix 使用 0600
- 原生 PowerShell SSH、tunnel、選單、設定編輯、版本與更新，不需要 Bash

## [0.4.0] - 2026-10-23

### Added
- `iap setup` / `bash scripts/setup.sh` 互動設定精靈：多主機、SSH / tunnel、入口、輸入檢查、覆寫確認與備份
- `install.sh --setup` 與 `--bin-dir PATH`
- 支援 `XDG_CONFIG_HOME` 與 setup 的 `--config PATH`

### Changed
- 範例改用通用專案與應用名稱；設定精靈不變更 gcloud 設定或啟動連線
- 安裝不覆寫既有的一般檔案；新設定與備份權限為 0600
- 修正 macOS Bash 3.2 在未指定 project / zone 時的空陣列錯誤與部分中文提示的變數解析

## [0.3.0] - 2026-10-23

### Added
- 設定檔支援 YAML（`hosts.yaml` / `hosts.yml`）與 JSON（`hosts.json`），含 `defaults` 區塊
- `iap to-yaml`：把純文字設定轉成 YAML
- `iap version`、`iap update`（git pull 更新）
- `iap names` 與 `completions/iap.bash` Tab 補全
- `install.sh`

## [0.2.0] - 2026-10-23

### Added
- 連線入口（endpoints）：tunnel 連上後列出網址 / 連線字串，支援 `{port}`、`{rport}`
- `iap show <name>`；fzf 選單即時預覽入口

### Changed
- 相容 macOS 內建 bash 3.2；沒有 `column` 時自動改用 awk 對齊

## [0.1.0] - 2026-10-23

### Added
- 互動選單（fzf / select）、`iap <name>` 直接連線
- ssh 與 start-iap-tunnel 兩種類型
- `iap import` 從 bash / zsh history 匯入
