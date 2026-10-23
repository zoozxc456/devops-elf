# Google IAP Client Manager

[English](README.md) | **繁體中文**

以 `iap` 指令管理 Google Cloud VM 的 IAP SSH 與 TCP tunnel 連線，提供 Bash 與原生 PowerShell 版本。

[版本紀錄](CHANGELOG.md) · [共用貢獻指南](../CONTRIBUTING.md) · [開發補充](CONTRIBUTING.md) · [安全補充](SECURITY.md) · [MIT 授權](LICENSE)

gcloud IAP 連線選單。把常連的 VM（SSH）和 port tunnel 寫進設定檔，不用再翻 history；啟動 tunnel 時會列出這台的入口（網址、DB 連線字串），連線建立後即可使用。

```
$ iap app-web
→ [app-web] localhost:18080  ⇢  app-vm:8080  連線中…
  連線入口（tunnel 建立後可用）：
  前台  http://localhost:18080/
  健康檢查  http://localhost:18080/health

✔ [app-web] 已連線  localhost:18080  ⇢  app-vm:8080
  (Ctrl-C 結束)
```

## 環境需求

| 用途 | Bash（macOS / Linux） | PowerShell（Windows / macOS / Linux） |
|---|---|---|
| 基本執行 | Bash 3.2+ 與一般 Unix 指令 | PowerShell 7.2+；不支援 Windows PowerShell 5.1 |
| 實際連線 | Google Cloud CLI（`gcloud`） | Google Cloud CLI（`gcloud`） |
| 純文字設定 | 無額外格式套件 | 原生支援 |
| JSON 設定 | `jq`；精靈輸出另需 Python 3 | 原生支援 |
| YAML 設定 | `jq`，另加 mikefarah `yq` 或 Python 3 + PyYAML | JSON 語法原生支援；一般 YAML 需 mikefarah `yq` |
| 指定連線編輯、移除、重設、解除安裝 | Python 3 | 原生支援 |
| 選用功能 | `fzf` 模糊搜尋；Git 用於更新 Git 來源 | Git 用於更新 Git 來源 |

本工具呼叫本機 `gcloud`，不代為申請 Google Cloud 權限或建立雲端資源。請先確認目標專案、VM 與 IAP 連線條件已由管理者設定，並完成帳號登入：

```bash
gcloud auth login
```

設定中的 project / zone 若使用 `-`，會採用目前 gcloud config；跨專案使用時建議明確填入。

## 安裝與快速開始

```bash
# 先取得原始碼，再進入專案目錄
cd google-iap-client-manager
bash install.sh --setup  # 安裝到 ~/.local/bin，接著執行設定精靈
```

依安裝畫面載入 shell 設定或開啟新終端機後，使用精靈建立的名稱連線：

```bash
iap ls            # 檢查連線清單
iap show app-web  # 顯示入口，不建立連線
iap app-web       # 建立 tunnel；名稱請換成自己的設定
iap app-vm        # SSH；名稱請換成自己的設定
```

不帶名稱執行 `iap` 可開啟選單。Tunnel 在前景執行，以 `Ctrl-C` 結束；入口提示會先顯示，實際可用時間以 gcloud 連線結果為準。

更新：

```bash
iap update  # 更新來源並自動複製新版到目前的 bin
iap version
```

安裝完成會顯示 `安裝版本：iap X.Y.Z`，更新完成會顯示 `更新完成：iap 舊版本 → iap 新版本`，版本相同時也會列出實際同步後的版號。

安裝時會在 bin 下的 `.iap/bash-source`（PowerShell 為 `powershell-source`）記錄來源目錄。`iap update` 若來源是 Git checkout，會先檢查未提交修改、執行 `git pull --ff-only --tags`，再自動更新已安裝的程式、精靈與補全；來源只是一般目錄時，則直接同步該目錄目前的版本。更新不會執行 setup 或修改連線設定。來源目錄刪除後仍能連線，但更新時需要從新的原始碼目錄重新安裝以刷新來源紀錄。

需要：`bash`、`gcloud`。`remove`、`reset`、`uninstall` 與 `edit <name>` 另需 Python 3。選用：`fzf`（模糊搜尋選單）、`jq`（JSON / YAML 設定）、`yq` 或 `python3` + PyYAML（YAML 設定）。

## 互動設定與新增連線

已有設定，想新增 SSH 或 tunnel 時執行：

```bash
iap new
# 或指定設定檔：
iap new --config /path/to/hosts
```

依序輸入連線名稱、`ssh` / `tunnel`、project、zone、VM instance；tunnel 另填 port。可加入多個入口，每次新增一組連線。`new` 保留既有連線，自動備份原檔，名稱重複時要求換名，中途取消不寫入。project / zone 預設 `-`，使用 gcloud config；需要特定專案時請明確填入。

純文字設定保留原有內容；JSON / YAML 保留既有資料，重新輸出為 JSON 語法，因此 YAML 註解與排版不會保留，可從備份查看。Bash 新增到一般 YAML 時另需 Python 3 + PyYAML 或 mikefarah yq；PowerShell 需要 mikefarah yq。`setup` 仍用於首次建立或整份重建。

首次建立或需要整份重建時，執行設定精靈：

```bash
# 尚未安裝時，在專案根目錄執行：
bash scripts/setup.sh

# 安裝後可從任意目錄執行：
iap setup

# 指定輸出（例如先在暫存目錄準備）：
iap setup --config /tmp/iap/hosts
```

依序輸入共用 project / zone、連線名稱、SSH 或 tunnel、各連線的 project / zone 與 VM instance。Tunnel 另填遠端／本機 port，可加入多個入口與多組連線。SSH 的 instance 可填 `user@instance`；tunnel 只填 instance。

Enter 使用顯示的預設值；project / zone 填 `-` 使用 gcloud config。精靈不會變更 gcloud config、登入或建立連線。設定完成後會列出檢查與連線指令；連線前請自行完成 `gcloud auth login`，並確保帳號具有目標 VM 所需的 IAP／SSH 權限。

預設產生無額外相依套件的純文字 `hosts`。既有 YAML / JSON 會維持檔名，使用 Python 3 產生 JSON 語法（也是合法 YAML）；讀取仍需安裝段落列出的格式相依套件。精靈不會讀取既有欄位，覆寫前預設取消，確認後才以新輸入重建，原檔存為同目錄的 `.backup-*`。設定與備份權限為 `0600`；中途取消不會寫入設定，拒絕覆寫符號連結。

僅安裝或指定安裝位置：

```bash
bash install.sh
bash install.sh --bin-dir "$HOME/bin" --setup
# 也相容原本的 BIN_DIR 環境變數
BIN_DIR="$HOME/bin" bash install.sh
```

安裝預設會將 bin 目錄持久加入 PATH：zsh 寫入 `${ZDOTDIR:-$HOME}/.zshrc`；Bash 寫入 `.bashrc` 與現有的登入設定（`.bash_profile`、`.bash_login`、`.profile` 依序選擇，皆無則建立 `.bash_profile`）。會先備份既有檔案，重跑不重複加入；請開啟新終端機，或依安裝畫面執行 `source`，讓目前終端機載入。

可用 `--shell bash` / `--shell zsh` 明確指定 shell、`--rc-file PATH` 指定寫入檔案，或 `--no-path` 只複製程式而不變更 PATH。`iap update` 自動略過 PATH 設定。Tab 補全仍依安裝畫面自行加入。

安裝會直接複製 `iap` 到 bin 目錄，並將 setup 與補全複製到同目錄下的 `.iap/`；不建立連結，移動或刪除原始碼後仍可使用。重新執行會更新已安裝的副本，也會將舊版 `iap` symlink 換成一般檔案；不覆寫無法辨識為本工具的既有一般檔案。

## PowerShell（Windows / macOS / Linux）

需要 **PowerShell 7.2+**（`pwsh`），不支援 Windows PowerShell 5.1。設定與連線均為原生 PowerShell，無需 Bash、WSL、Python 或 jq；實際連線另需安裝 `gcloud`。

在專案根目錄執行安裝與設定：

```powershell
pwsh -NoProfile -File .\install.ps1 -Setup
# 自訂安裝位置：
pwsh -NoProfile -File .\install.ps1 -BinDir "$HOME\bin" -Setup

# 只建立設定，不安裝：
pwsh -NoProfile -File .\scripts\setup.ps1
pwsh -NoProfile -File .\scripts\setup.ps1 -Config "$HOME\iap-config\hosts.json"
```

預設直接將 `iap.ps1` 複製到 `$HOME/.local/bin`，setup、共用函式及補全則複製到 bin 目錄下的 `.iap/`，不依賴原始碼目錄。重新安裝會更新本工具的副本，並將舊版啟動腳本換成完整程式。更新時執行 `iap update` 即可，會依來源類型更新 Git 或同步本機版本，再自動複製到目前的安裝位置。

Windows 安裝預設直接更新使用者 PATH，無需系統管理員權限；macOS / Linux 則寫入 `$PROFILE.CurrentUserAllHosts`，先備份且不重複加入。兩者也會更新安裝程序本身的 PATH。從現有 PowerShell 用 `& ./install.ps1` 執行可立即使用；若使用 `pwsh -File` 啟動子程序，父終端機需開啟新工作階段。可用 `-NoPath` 略過設定，或 `-ProfilePath PATH` 明確選擇 profile 檔案（Windows 指定此選項時也改用 profile 持久設定）。補全仍可依畫面指令加入 `$PROFILE`。未加入 PATH 時仍可直接執行：

```powershell
pwsh -NoProfile -File .\iap.ps1 setup
pwsh -NoProfile -File .\iap.ps1 ls
pwsh -NoProfile -File .\iap.ps1 app-vm

# 加入 PATH 後，在 PowerShell 執行：
iap setup -Config "$HOME\iap-config\hosts.json"
iap new -Config "$HOME\iap-config\hosts.json"
$env:IAP_CONF = "$HOME\iap-config\hosts.json"
iap ls
iap show app-web
iap app-web

# 補全，可加到 $PROFILE（路徑換成實際 clone 位置）：
. "$HOME\.local\bin\.iap\completions\iap.ps1"
```

與 Bash 版使用相同的設定搜尋順序、`IAP_CONF`、`XDG_CONFIG_HOME` 與重建／備份規則。PowerShell 精靈的 YAML 也採用 JSON 語法，因此不需 YAML 套件；手寫的一般 YAML 需另外安裝 mikefarah 版 `yq`。產物使用 UTF-8（無 BOM）與 LF；Unix 權限為 `0600`，Windows 設定檔與備份使用僅目前使用者可存取的 ACL。

PowerShell 版支援數字選單、直接 SSH / tunnel，以及下表的管理指令。`import`、`to-yaml` 及 fzf 選單目前仍由 Bash 版提供。macOS / Linux 若同時安裝兩版，可使用 `iap.ps1` 明確選擇 PowerShell 版。

## 管理連線與解除安裝

匯出目前選用的設定（依 `IAP_CONF` 或預設搜尋順序）：

```bash
iap export                         # 顯示設定內容，不修改任何檔案
iap export ~/iap-backup/hosts       # 匯出到指定檔案
iap export --output ~/iap-backup/hosts
```

PowerShell 同樣支援 `iap export FILE`，也可寫成 `iap export -Output FILE`。指定輸出檔案時會完整複製原始內容，保留註解、格式、換行及 BOM，不進行 YAML / JSON 格式轉換；備份檔請沿用原本的設定格式。既有輸出檔預設不覆寫，明確確認後先備份；不可輸出到目前設定檔本身或符號連結。Unix 匯出檔權限為 `0600`，Windows 使用個人 ACL。只匯出單一選用設定檔，不包含其他歷史備份或程式安裝資訊。

```bash
iap edit oneclick-db    # 只編輯這一組連線（含入口）
iap remove oneclick-db  # 移除這一組連線（含入口）
iap reset               # 清空目前設定檔中的所有連線
iap uninstall           # 移除目前這個 shell 版本的安裝，保留設定
```

`setup` 偵測到既有設定時，會先警告重建影響及顯示檔案路徑，預設不覆寫；確認後也會先備份。新增請用 `new`，只修改特定連線請用 `edit <name>`。

`edit <name>` 將該連線複製到權限受限的暫存檔，再開啟 `$EDITOR`（Bash 預設 `vi`；PowerShell 在 Windows 預設記事本，其他平台預設 `vi`）。儲存並關閉編輯器後，程式檢查連線名稱、類型與 port，再詢問是否存回。請保留原本名稱，不可加入第二組連線或改動共用 defaults；未修改、取消、編輯器失敗或格式錯誤時不會寫入。`iap edit` 不帶名稱仍會直接開啟整份設定檔。

`remove`、`reset`、`uninstall` 都會先顯示影響範圍，只有明確輸入 `y` / `yes` 才執行，Enter 預設取消。`reset` 只清空目前選用設定檔的連線，保留 JSON / YAML 的 defaults 與其他共用欄位；其他設定檔及備份不受影響。

修改、移除或重設前會建立同目錄的 `.backup-*`，Unix 權限為 `0600`，Windows 使用個人 ACL。JSON / YAML 管理操作會重新序列化成 JSON 語法，YAML 註解及排版可從備份查看。設定若在操作期間被其他程序修改，程式會停止寫入。

`uninstall` 僅供複製安裝版使用：Bash 移除 `iap` 及其配套檔；PowerShell 移除 `iap.ps1` 及其配套檔。兩版同時安裝時會保留另一版，以及使用者設定、備份與原始碼。shell rc / `$PROFILE` 內手動加入的補全載入行需自行移除。

## 指令

| 指令 | 說明 |
|---|---|
| `iap help` / `iap --help` / `iap -h` | 顯示使用說明 |
| `iap export [FILE]` | 匯出目前設定，保留原始格式；省略 FILE 則顯示內容 |
| `iap setup [--config PATH]` | 互動建立／重建設定並備份 |
| `iap new [--config PATH]` | 新增一組 SSH / tunnel，保留既有設定並備份 |
| `iap` | 互動選單（有 fzf 用 fzf） |
| `iap <name> [-- ssh 參數]` | 直接連線 |
| `iap show <name>` | 只看入口，不連線 |
| `iap ls` | 列出主機 |
| `iap edit [name]` | 編輯整份設定／只編輯指定連線 |
| `iap remove <name>` | 確認並備份後移除指定連線 |
| `iap reset` | 確認並備份後清空目前設定的全部連線 |
| `iap uninstall` | 確認後移除目前版本的安裝，保留設定 |
| `iap import` | 從 shell history 撈 gcloud 指令 |
| `iap to-yaml` | 純文字設定轉 YAML |
| `iap version` / `iap update` | 版本 / 更新來源並自動更新安裝副本 |

## 設定檔

預設目錄為 `${XDG_CONFIG_HOME:-$HOME/.config}/iap`，依序找第一個存在的 `hosts.yaml`、`hosts.yml`、`hosts.json`、`hosts`。也可用 `IAP_CONF=/path/to/file` 指定；精靈的 `--config PATH` 優先於 `IAP_CONF`，且只影響本次輸出。若在其他路徑建立設定，後續指令也需指定 `IAP_CONF`。

YAML 範例見 [`examples/hosts.yaml`](examples/hosts.yaml)。純文字格式：

```
# name       type    project      zone          instance        [remote_port] [local_port]
app-web   tunnel  my-project  us-central1-a  app-vm  8080  18080
  > 健康檢查 http://localhost:{port}/health
app-vm  ssh     my-project  us-central1-a  app-vm
```

純文字欄位以空白分隔，名稱與各欄位不可包含空白。`type` 為 `ssh` 或 `tunnel`；tunnel 必填遠端 port，本機 port 省略時使用遠端 port。入口行以 `>` 開頭，歸屬於上一組連線，`{port}` / `{rport}` 分別代入本機／遠端 port。入口只用於顯示，不會自動開啟瀏覽器或資料庫用戶端。

YAML / JSON 的最外層使用 `hosts` 物件，可加上 `defaults.project` / `defaults.zone`。各連線省略 `type` 時預設為 `ssh`，省略 `instance` 時使用連線名稱；詳細範例見上方連結。請勿使用 `setup`、`new`、`help`、`export` 等指令名稱作為連線名稱。

預設設定儲存在原始碼目錄外。請勿將真實主機設定、憑證、匯出檔或備份提交到版本庫；現有 `.gitignore` 不會涵蓋所有自訂檔名。`iap update` 只更新程式與配套檔案，不會動到連線設定。

## Tab 補全

```bash
source ~/.local/bin/.iap/completions/iap.bash   # 加到 ~/.bashrc 或 ~/.zshrc
```

## 常見問題

| 情況 | 檢查方式 |
|---|---|
| 安裝後找不到 `iap` | 開啟新終端機，或依安裝輸出載入 shell rc / profile；確認安裝目錄在 PATH 中 |
| 找不到設定或清單與預期不同 | 檢查 `IAP_CONF`、`XDG_CONFIG_HOME` 與設定搜尋順序；`--config` 只影響當次精靈 |
| YAML / JSON 無法讀取 | 依環境需求安裝格式套件；`yq` 須為 mikefarah 版本 |
| gcloud 連線被拒絕 | 檢查登入帳號、project、zone、VM 名稱，以及 IAP／SSH 權限與雲端網路設定 |
| 本機 port 已被使用 | 用 `iap edit <name>` 調整 `local_port`，或先停止占用該 port 的程序 |
| `iap update` 失敗 | 保留安裝來源目錄；Git 來源需先處理未提交修改；來源搬移後重新安裝 |
| 修改 YAML 後註解消失 | 管理指令會重新輸出 JSON 語法；原註解與排版可在 `.backup-*` 查看 |

## 開發與貢獻

開發流程、測試範圍與發布檢查見 [CONTRIBUTING.md](CONTRIBUTING.md)。安全問題請依根目錄 [SECURITY.md](../SECURITY.md) 私下回報；IAP 特殊行為見 [安全補充](SECURITY.md)。

## 驗證

```bash
python3 -m unittest discover -s tests -v
```

測試使用暫存設定與假的 gcloud，不會連線 Google Cloud 或改動個人設定。PowerShell 測試需要 PATH 中有 `pwsh`，未安裝時會跳過；Windows ACL 分支須在 Windows 執行驗證。

## 授權

本專案採用 [MIT License](LICENSE)。
