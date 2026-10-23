# 版本管理

`VERSION` 是 Lookout 專案版本的唯一來源，目前為 **1.0.0**。核心、插件、Ansible 與設定精靈共用同一版本；Docker 映像及 Ansible collection 的版本各自維護，不隨專案版本自動更新。

現有功能統一收錄為第一個正式版本，不將先前同日的開發步驟虛構為多次發版。每次正式版本都在 CHANGELOG.md 有日期與變更說明；下一版的內容先填在最上方 `[Unreleased]`。

## 版本規則

| 類型 | 使用時機 | 範例 |
|---|---|---|
| patch | 相容的錯誤修正、文件修正 | 1.0.0 → 1.0.1 |
| minor | 新增可選功能／插件，既有部署方式仍相容 | 1.0.0 → 1.1.0 |
| major | 不相容的設定、label、部署介面或資料格式調整 | 1.0.0 → 2.0.0 |

若更新需要修改既有 `.env`、inventory、掛載路徑或人工遷移資料，須在該版 CHANGELOG 明確寫出影響與升級步驟。版本工具目前處理正式的 `major.minor.patch`，不處理預發行版本。

## 日常與發版

在 lookout 根目錄執行，需要 Python 3（Windows 可把 `python3` 換成 `py -3`）：

```bash
python3 scripts/version.py show
python3 scripts/version.py check
```

開發期間先在 CHANGELOG.md 的 `[Unreleased]` 加入本次變更，再依性質更新：

```bash
# 預覽，不修改檔案
python3 scripts/version.py bump patch --dry-run

# 選擇一個符合本次變更的類型
python3 scripts/version.py bump patch
# python3 scripts/version.py bump minor
# python3 scripts/version.py bump major
```

工具會提升 VERSION、把 Unreleased 的內容移至新版本，並保留新的空白 Unreleased 區塊。日期預設採 UTC+8 當天；需要指定日期時可使用 `--date YYYY-MM-DD`。沒有變更說明、版本重複或版本不一致時會停止。

更新後執行相關測試與設定檢查：

```bash
python3 scripts/version.py check
python3 -m unittest discover -s tests -p 'test_*.py'
./scripts/check.sh
./scripts/check.sh odoo nginx
```

`check.sh` 已包含版本一致性檢查。PowerShell／Ansible 流程測試需要對應工具，工具缺少時 unittest 會標記 skip；發版時應確認修改範圍所需的檢查實際有執行。

## Git 標記

版本工具不執行 commit、tag、push 或部署。目前工作目錄尚未建立 Git 版本庫；納入 Git 後，先 review 並提交本版內容，再為已提交的版本建立附註標記：

```bash
git tag -a lookout-v1.0.0 -m "Lookout 1.0.0"
```

後續將 tag 名稱與訊息換成 VERSION 的實際值。採 `lookout-vX.Y.Z` 可與其他 devops 元件的版本區分；VERSION 檔本身只放 `X.Y.Z`。

## 部署版本追蹤

Ansible 會將本次來源版本複製到遠端：

```text
/opt/lookout/server/VERSION
/opt/lookout/agent/VERSION
```

路徑隨 `lookout_root` 調整；只部署 Agent 時不會改寫 Server 的版本紀錄。這些檔案記錄來源版本，仍須通過部署與健康檢查才能視為成功更新。

手動執行 `plugins.py apply` 時，Agent 與 Server 的 `generated/.lookout-generated` 也會記錄產生時的版本與啟用插件。版本更新後須重新 apply 並依操作文件更新容器；只修改 VERSION 不會部署服務或更新資料。
