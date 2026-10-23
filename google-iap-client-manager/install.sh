#!/usr/bin/env bash
# 安裝 iap：複製程式與設定精靈到 BIN_DIR，不依賴原始碼目錄。
#   ./install.sh                 裝到 ~/.local/bin
#   BIN_DIR=/usr/local/bin ./install.sh
#   ./install.sh --setup       安裝後執行設定精靈
set -euo pipefail

REPO_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SETUP=false
ADD_PATH=true
TARGET_SHELL="${SHELL:-/bin/bash}"
TARGET_SHELL=${TARGET_SHELL##*/}
TARGET_SHELL=${TARGET_SHELL:-bash}
RC_FILE=
while [[ $# -gt 0 ]]; do
  case $1 in
    --setup) SETUP=true; shift ;;
    --no-path) ADD_PATH=false; shift ;;
    --shell) [[ $# -ge 2 ]] || exit 1; TARGET_SHELL=$2; shift 2 ;;
    --rc-file) [[ $# -ge 2 && -n $2 ]] || exit 1; RC_FILE=$2; shift 2 ;;
    --bin-dir) [[ $# -ge 2 && -n $2 ]] || { echo '缺少 --bin-dir PATH' >&2; exit 1; }; BIN_DIR=$2; shift 2 ;;
    -h|--help)
      echo '用法：bash install.sh [--bin-dir PATH] [--setup] [--no-path] [--shell bash|zsh] [--rc-file PATH]'
      echo 'BIN_DIR 預設 ~/.local/bin；--setup 安裝後互動建立連線設定。'
      echo '預設持久加入 shell PATH；--no-path 只複製安裝，不修改 shell 設定。'
      exit 0 ;;
    *) echo "未知參數：$1" >&2; exit 1 ;;
  esac
done

mkdir -p "$BIN_DIR"
BIN_DIR="$(cd "$BIN_DIR" && pwd)"
[[ "$BIN_DIR" != "$REPO_DIR" ]] || { echo '安裝目錄不可為原始碼目錄。' >&2; exit 1; }
if [[ -e "$BIN_DIR/iap" && ! -L "$BIN_DIR/iap" ]] &&
   { [[ ! -f "$BIN_DIR/iap" ]] || ! head -n 2 "$BIN_DIR/iap" | grep -q '^# iap — gcloud IAP'; }; then
  echo "拒絕覆寫既有檔案：$BIN_DIR/iap" >&2
  exit 1
fi
# 舊版 symlink 僅移除連結本身，避免 cp 寫回原始碼。
[[ ! -L "$BIN_DIR/iap" ]] || rm "$BIN_DIR/iap"
mkdir -p "$BIN_DIR/.iap/scripts" "$BIN_DIR/.iap/completions"
cp "$REPO_DIR/iap" "$BIN_DIR/iap"
chmod 755 "$BIN_DIR/iap"
cp "$REPO_DIR/scripts/setup.sh" "$BIN_DIR/.iap/scripts/setup.sh"
cp "$REPO_DIR/scripts/manage.py" "$BIN_DIR/.iap/scripts/manage.py"
cp "$REPO_DIR/completions/iap.bash" "$BIN_DIR/.iap/completions/iap.bash"
printf '%s\n' "$REPO_DIR" > "$BIN_DIR/.iap/bash-source"
chmod 600 "$BIN_DIR/.iap/bash-source"
echo "✔ 已複製安裝：$BIN_DIR/iap"
echo "✔ 安裝版本：$(bash "$BIN_DIR/iap" version)"

quote_shell() { local value=${1//\'/\'\\\'\'}; printf "'%s'" "$value"; }
persist_path() {
  local profile=$1 marker backup
  marker="# iap PATH: $BIN_DIR"
  [[ ! -e "$profile" || -f "$profile" ]] || { echo "shell 設定不是一般檔案：$profile" >&2; return 1; }
  if [[ -f "$profile" ]] && grep -Fxq -- "$marker" "$profile"; then
    echo "✔ PATH 已設定：$profile"; return
  fi
  mkdir -p "$(dirname "$profile")"
  if [[ -f "$profile" ]]; then
    backup=$(mktemp "${profile}.backup-XXXXXX")
    cp "$profile" "$backup"
    chmod 600 "$backup"
    echo "shell 設定備份：$backup"
  fi
  (
    umask 077
    printf '\n%s\n' "$marker"
    printf 'case ":$PATH:" in\n  *:%s:*) ;;\n  *) export PATH=%s:"$PATH" ;;\nesac\n' "$(quote_shell "$BIN_DIR")" "$(quote_shell "$BIN_DIR")"
  ) >> "$profile"
  echo "✔ 已加入 PATH：$profile"
}
if [[ $ADD_PATH == true ]]; then
  if [[ -n "$RC_FILE" ]]; then
    persist_path "$RC_FILE"
  else
    case $TARGET_SHELL in
      zsh) RC_FILE="${ZDOTDIR:-$HOME}/.zshrc"; persist_path "$RC_FILE" ;;
      bash)
        RC_FILE="$HOME/.bashrc"; persist_path "$RC_FILE"
        login_profile="$HOME/.bash_profile"
        for profile in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
          if [[ -f "$profile" ]]; then login_profile=$profile; break; fi
        done
        persist_path "$login_profile" ;;
      *) echo "無法自動設定 $TARGET_SHELL 的 PATH，請用 --shell bash 或 --shell zsh 指定。" >&2; exit 1 ;;
    esac
  fi
  echo "請開啟新終端機，或在目前 shell 執行：source $(quote_shell "$RC_FILE")"
fi

cat <<EOF

Tab 補全（選用），在 ~/.bashrc 或 ~/.zshrc 加：
  source "$BIN_DIR/.iap/completions/iap.bash"

建立設定檔：
  iap setup                           # 互動設定精靈
  iap new                             # 新增一組連線，保留既有設定
  iap import                          # 從 history 撈，檢查後貼入設定
  # 或參考 $REPO_DIR/examples/hosts.yaml
EOF

if [[ "$SETUP" == true ]]; then
  bash "$BIN_DIR/.iap/scripts/setup.sh"
fi
