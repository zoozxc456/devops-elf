#!/usr/bin/env bash
# Bash 3.2+：互動建立 Ansible 或直接 Compose 部署設定；不執行部署。
set +x
set -euo pipefail
umask 077
SOURCE_ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT_ROOT=$SOURCE_ROOT
MODE=
WORK=

usage() {
  cat <<'HELP'
用法：bash scripts/setup.sh [ansible|server|agent] [--output-dir PATH]

不帶模式會顯示選單。
  ansible  產生 deploy/inventory.local.yml 與加密的 vault.yml
  server   產生 server/.env，並組合所選插件
  agent    產生 agent/.env，並組合所選插件

--output-dir 指定設定輸出根目錄（預設 lookout/）；不會複製程式碼。
精靈不會 SSH、安裝套件、建立 Docker 網路或啟動服務。
HELP
}
while [[ $# -gt 0 ]]; do
  case $1 in
    ansible|server|agent) MODE=$1; shift ;;
    --output-dir) [[ $# -ge 2 ]] || { usage >&2; exit 1; }; OUTPUT_ROOT=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done
cleanup() { [[ -z "$WORK" ]] || rm -rf "$WORK"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Never source/eval user input, .env or inventory. Read all values as literal text.
ask() {
  local label=$1 default=$2 validator=$3 input
  while true; do
    printf '%s' "$label" >&2
    [[ -z "$default" ]] || printf ' [%s]' "$default" >&2
    printf ': ' >&2
    IFS= read -r input || { printf '\n已取消，未寫入設定。\n' >&2; exit 1; }
    input=${input:-$default}
    if "$validator" "$input"; then ANSWER=$input; return; fi
    printf '格式不符，請重新輸入。\n' >&2
  done
}
yes_no() {
  local label=$1 default=$2 input
  while true; do
    printf '%s [%s]: ' "$label" "$default" >&2
    IFS= read -r input || exit 1
    if [[ -z "$input" ]]; then
      if [[ "$default" == Y/n ]]; then input=y; else input=n; fi
    fi
    case $input in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) printf '請輸入 y 或 n。\n' >&2 ;;
    esac
  done
}
plain() { [[ $1 != *"'"* && ! $1 =~ [[:cntrl:]] && $1 != *'{{'* && $1 != *'{%'* ]]; }
nonempty() { [[ -n $1 ]] && plain "$1"; }
identifier() { [[ $1 =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; }
ssh_host() { [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; }
network() { [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; }
path_value() { [[ $1 =~ ^/[a-zA-Z0-9_./-]+$ && $1 != / && $1 != *'/../'* && $1 != */.. ]]; }
ipv4() {
  local octet parts
  [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
  local IFS=.
  read -r -a parts <<< "$1"
  for octet in "${parts[@]}"; do
    [[ ${#octet} -eq 1 || $octet != 0* ]] || return 1
    (( 10#$octet <= 255 )) || return 1
  done
}
server_ip() { ipv4 "$1" && [[ $1 != 0.0.0.0 && $1 != 127.* && $1 != 192.0.2.10 ]]; }
url() { [[ $1 =~ ^https?://[^[:space:]]+$ ]] && plain "$1"; }
timezone() { [[ $1 == browser || $1 == UTC || $1 =~ ^[A-Za-z_+-]+(/[A-Za-z0-9_+-]+)+$ ]]; }
positive() { [[ $1 =~ ^[1-9][0-9]{0,5}$ ]]; }
count() { [[ $1 =~ ^([0-9]|[1-4][0-9]|50)$ ]]; }
quote_yaml() { local value=${1//\'/\'\'}; printf "'%s'" "$value"; }
yaml_value() { printf '    %s: ' "$1"; quote_yaml "$2"; printf '\n'; }
env_value() { printf "%s='%s'\n" "$1" "$2"; }
secret() {
  local first second
  while true; do
    printf 'Grafana 管理員密碼（不顯示，不能含單引號或換行）: ' >&2
    IFS= read -rs first || exit 1
    printf '\n再次輸入密碼: ' >&2
    IFS= read -rs second || exit 1
    printf '\n' >&2
    if [[ -n "$first" && "$first" != CHANGE_ME && "$first" == "$second" ]] && plain "$first"; then
      GRAFANA_PASSWORD=$first; return
    fi
    printf '密碼不符、為空或含不支援的字元，請重新輸入。\n' >&2
  done
}
plugins() {
  PLUGINS=()
  yes_no '啟用 Odoo 插件？' 'y/N' && PLUGINS+=(odoo)
  yes_no '啟用 Nginx 插件？' 'y/N' && PLUGINS+=(nginx)
  return 0
}
# Confirm replacing local files before gathering secrets. Backup is published only on success.
replace_ok() {
  [[ ! -L "$1" ]] || { printf '拒絕覆寫符號連結：%s\n' "$1" >&2; exit 1; }
  if [[ -e "$1" ]]; then
    [[ -f "$1" ]] || { printf '目標不是一般檔案：%s\n' "$1" >&2; exit 1; }
    yes_no "已有 $1，將重建並備份原檔，是否繼續？" 'y/N' || exit 0
  fi
}
publish() {
  local source=$1 target=$2 backup staged
  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]]; then
    backup=$(mktemp "${target}.backup-XXXXXX")
    cp "$target" "$backup"
    chmod 600 "$backup"
    printf '原檔備份：%s\n' "$backup"
  fi
  staged=$(mktemp "${target}.tmp-XXXXXX")
  cp "$source" "$staged"
  chmod 600 "$staged"
  mv -f "$staged" "$target"
  printf '已寫入：%s\n' "$target"
}
server_settings() {
  ask '監控主機內網／VPN IPv4（容器可連線，不能填 localhost）' '10.0.0.10' server_ip; SERVER_IP=$ANSWER
  ask 'Grafana 綁定 IPv4' '127.0.0.1' ipv4; GRAFANA_BIND=$ANSWER
  ask 'Grafana 瀏覽器網址' 'http://localhost:3000' url; GRAFANA_URL=$ANSWER
  ask 'Grafana 時區' 'browser' timezone; GRAFANA_TZ=$ANSWER
  ask 'Grafana 管理員帳號' 'admin' identifier; GRAFANA_USER=$ANSWER
  ask 'Prometheus 保留天數' '30' positive; PROM_DAYS=$ANSWER
  ask 'Loki prod log 保留小時（至少 24）' '720' positive; LOKI_HOURS=$ANSWER
  while (( LOKI_HOURS < 24 )); do ask '請填至少 24 小時' '720' positive; LOKI_HOURS=$ANSWER; done
  ask 'Loki 非 prod log 保留小時（至少 24）' '168' positive; NONPROD_HOURS=$ANSWER
  while (( NONPROD_HOURS < 24 || NONPROD_HOURS > LOKI_HOURS )); do
    ask "請填 24 到 $LOKI_HOURS 小時" "$LOKI_HOURS" positive; NONPROD_HOURS=$ANSWER
  done
}

if [[ -z "$MODE" ]]; then
  printf 'Lookout 設定精靈\n1. Ansible 部署設定（建議）\n2. 本機 Server .env\n3. 本機 Agent .env\n' >&2
  menu() { [[ $1 == 1 || $1 == 2 || $1 == 3 ]]; }
  ask '選擇模式' '1' menu
  case $ANSWER in 1) MODE=ansible ;; 2) MODE=server ;; 3) MODE=agent ;; esac
fi
command -v python3 >/dev/null || { printf '請先安裝 Python 3（插件產生器需要）。\n' >&2; exit 1; }
if [[ "$MODE" == ansible ]]; then
  command -v ansible-vault >/dev/null || { printf '請先安裝 Ansible：pipx install ansible-core，並確認 ansible-vault 在 PATH。\n' >&2; exit 1; }
fi
mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT=$(cd "$OUTPUT_ROOT" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lookout-setup.XXXXXX")

if [[ "$MODE" == ansible ]]; then
  INVENTORY=$OUTPUT_ROOT/deploy/inventory.local.yml
  VAULT=$OUTPUT_ROOT/deploy/group_vars/all/vault.yml
  replace_ok "$INVENTORY"
  NEW_VAULT=true
  if [[ -e "$VAULT" ]]; then
    [[ -f "$VAULT" && ! -L "$VAULT" && $(head -c 14 "$VAULT") == '$ANSIBLE_VAULT' ]] || {
      printf '既有 vault.yml 不是加密的一般檔案，請先自行加密／整理後重試。\n' >&2; exit 1;
    }
    NEW_VAULT=false
    printf '保留既有加密 Vault（含 Grafana 密碼與資料庫 secrets）。\n' >&2
  fi
  ask 'SSH 使用者' "${USER:-deploy}" identifier; SSH_USER=$ANSWER
  ask '監控主機 inventory 名稱' 'monitoring' identifier; SERVER_NAME=$ANSWER
  ask '監控主機 SSH 位址（IP 或 DNS）' '10.0.0.10' ssh_host; SSH_ADDRESS=$ANSWER
  ask '遠端部署目錄' '/opt/lookout' path_value; REMOTE_ROOT=$ANSWER
  server_settings
  ask '遠端監控資料目錄（磁碟須已掛好）' "$REMOTE_ROOT/server/data" path_value; DATA_DIR=$ANSWER
  plugins
  SERVER_AGENT=false
  if yes_no '監控主機也部署 Agent，監控自身資源？' 'Y/n'; then
    SERVER_AGENT=true
    ask '監控主機 Agent 使用的 Docker 網路（須已存在）' 'app' network; SERVER_NETWORK=$ANSWER
  fi
  ask '另外加入幾台應用 Agent 主機（0–50）' '1' count; AGENT_COUNT=$ANSWER
  # Host-level vars override group_vars/all/main.yml without changing shared tracked defaults.
  {
    printf 'all:\n  children:\n    lookout_server:\n      hosts:\n        %s:\n    lookout_agent:\n      hosts:' "$SERVER_NAME"
    if [[ "$SERVER_AGENT" == true || "$AGENT_COUNT" != 0 ]]; then
      printf '\n'
      [[ "$SERVER_AGENT" != true ]] || printf '        %s:\n' "$SERVER_NAME"
      # Entries are appended after collecting each host below.
    else
      printf ' {}\n'
    fi
  } > "$WORK/groups.yml"
  # Hosts are written under all.hosts and reused by both children groups.
  printf '  hosts:\n' > "$WORK/hosts.yml"
  write_common_host() {
    printf '    %s:\n' "$1"
    # yaml_value emits four spaces; nesting requires another two.
    {
      yaml_value ansible_host "$2"
      yaml_value ansible_user "$SSH_USER"
      yaml_value lookout_root "$REMOTE_ROOT"
      yaml_value lookout_server_ip "$SERVER_IP"
      printf '    lookout_plugins: ['
      local separator= plugin
      for plugin in "${PLUGINS[@]+${PLUGINS[@]}}"; do printf '%s%s' "$separator" "$plugin"; separator=', '; done
      printf ']\n'
    } | sed 's/^/  /'
  }
  write_common_host "$SERVER_NAME" "$SSH_ADDRESS" >> "$WORK/hosts.yml"
  {
    yaml_value grafana_admin_user "$GRAFANA_USER"
    yaml_value grafana_bind_addr "$GRAFANA_BIND"
    yaml_value grafana_root_url "$GRAFANA_URL"
    yaml_value grafana_timezone "$GRAFANA_TZ"
    yaml_value prometheus_retention "${PROM_DAYS}d"
    yaml_value loki_retention "${LOKI_HOURS}h"
    yaml_value loki_retention_nonprod "${NONPROD_HOURS}h"
    yaml_value lookout_data_dir "$DATA_DIR"
    if [[ "$SERVER_AGENT" == true ]]; then yaml_value app_network "$SERVER_NETWORK"; yaml_value host_role prod; fi
  } | sed 's/^/  /' >> "$WORK/hosts.yml"
  USED_NAMES="|$SERVER_NAME|"
  for (( index=1; index<=AGENT_COUNT; index++ )); do
    printf '\n應用 Agent %s/%s\n' "$index" "$AGENT_COUNT" >&2
    while true; do
      ask 'inventory 名稱（每台須唯一）' "app-$index" identifier; HOST_NAME=$ANSWER
      [[ "$USED_NAMES" != *"|$HOST_NAME|"* ]] && break
      printf '名稱已存在，請換一個。\n' >&2
    done
    USED_NAMES="$USED_NAMES$HOST_NAME|"
    ask 'SSH 位址（IP 或 DNS）' "10.0.0.$((20+index))" ssh_host; HOST_ADDRESS=$ANSWER
    ask '主機環境／角色' 'prod' identifier; HOST_ROLE=$ANSWER
    ask '應用 Docker 網路（須已存在）' 'app' network; APP_NETWORK=$ANSWER
    ask '允許收集的環境 regex' "$HOST_ROLE" nonempty; ENVS=$ANSWER
    printf '        %s:\n' "$HOST_NAME" >> "$WORK/groups.yml"
    write_common_host "$HOST_NAME" "$HOST_ADDRESS" >> "$WORK/hosts.yml"
    { yaml_value host_role "$HOST_ROLE"; yaml_value app_network "$APP_NETWORK"; yaml_value lookout_envs "$ENVS"; } | sed 's/^/  /' >> "$WORK/hosts.yml"
  done
  cat "$WORK/groups.yml" "$WORK/hosts.yml" > "$WORK/inventory.yml"
  printf '\n將建立：%s\n監控：%s（%s），額外 Agent：%s 台\n部署目錄：%s\n' "$INVENTORY" "$SERVER_NAME" "$SERVER_IP" "$AGENT_COUNT" "$REMOTE_ROOT"
  if [[ "$NEW_VAULT" == true ]]; then
    secret
    printf 'vault_grafana_admin_password: !unsafe ' > "$WORK/vault.plain.yml"
    quote_yaml "$GRAFANA_PASSWORD" >> "$WORK/vault.plain.yml"
    printf '\nvault_alertmanager_secrets: {}\nvault_lookout_agent_env: {}\n' >> "$WORK/vault.plain.yml"
    unset GRAFANA_PASSWORD
    printf '\n接著設定 Vault 加密密碼，這組密碼在部署時使用。\n' >&2
    ansible-vault encrypt --output "$WORK/vault.yml" "$WORK/vault.plain.yml"
    rm -f "$WORK/vault.plain.yml"
    publish "$WORK/vault.yml" "$VAULT"
  fi
  publish "$WORK/inventory.yml" "$INVENTORY"
  printf '\n設定完成。請在包含 site.yml 的 deploy/ 目錄執行：\n'
  printf 'cd %q\n' "$OUTPUT_ROOT/deploy"
  printf 'ansible-galaxy collection install -r requirements.yml -p .collections\n'
  printf 'ansible all -i inventory.local.yml -m ping --ask-vault-pass\n'
  printf 'ansible-playbook -i inventory.local.yml site.yml --syntax-check --ask-vault-pass\n'
  printf 'ansible-playbook -i inventory.local.yml site.yml --ask-vault-pass\n'
  printf 'sudo 需要密碼時，在部署指令加 --ask-become-pass。SSH key 使用 ssh-agent 或 Ansible 的 --private-key。\n'
else
  TARGET=$OUTPUT_ROOT/$MODE/.env
  replace_ok "$TARGET"
  if [[ "$MODE" == server ]]; then
    server_settings
    ask '監控資料目錄（使用預設也請保留完整絕對路徑）' "$OUTPUT_ROOT/server/data" path_value; DATA_DIR=$ANSWER
    plugins
    secret
    {
      env_value BIND_ADDR "$SERVER_IP"
      env_value GRAFANA_BIND_ADDR "$GRAFANA_BIND"
      env_value GRAFANA_ADMIN_USER "$GRAFANA_USER"
      env_value GRAFANA_ADMIN_PASSWORD "$GRAFANA_PASSWORD"
      env_value GRAFANA_ROOT_URL "$GRAFANA_URL"
      env_value GRAFANA_TIMEZONE "$GRAFANA_TZ"
      env_value PROMETHEUS_RETENTION "${PROM_DAYS}d"
      env_value LOKI_RETENTION "${LOKI_HOURS}h"
      env_value LOKI_RETENTION_NONPROD "${NONPROD_HOURS}h"
      env_value LOOKOUT_DATA_DIR "$DATA_DIR"
    } > "$WORK/.env"
    unset GRAFANA_PASSWORD
  else
    ask '這台 Agent 的唯一名稱' 'app-01' identifier; HOST_NAME=$ANSWER
    ask '主機環境／角色' 'prod' identifier; HOST_ROLE=$ANSWER
    ask '應用 Docker 網路（須已存在）' 'app' network; APP_NETWORK=$ANSWER
    ask '允許收集的環境 regex' "$HOST_ROLE" nonempty; ENVS=$ANSWER
    ask '依名稱收 log 的容器 regex（留空表示只收有 label 的容器）' '' plain; CONTAINERS=$ANSWER
    ask '監控主機內網／VPN IPv4' '10.0.0.10' server_ip; SERVER_IP=$ANSWER
    plugins
    {
      env_value HOST_NAME "$HOST_NAME"
      env_value HOST_ROLE "$HOST_ROLE"
      env_value APP_NETWORK "$APP_NETWORK"
      env_value LOOKOUT_ENVS "$ENVS"
      env_value LOOKOUT_CONTAINERS "$CONTAINERS"
      env_value LOKI_PUSH_URL "http://$SERVER_IP:3100/loki/api/v1/push"
      env_value PROMETHEUS_REMOTE_WRITE_URL "http://$SERVER_IP:9090/api/v1/write"
    } > "$WORK/.env"
  fi
  (umask 022; python3 "$SOURCE_ROOT/scripts/plugins.py" apply --output "$OUTPUT_ROOT" "${PLUGINS[@]+${PLUGINS[@]}}" >/dev/null)
  publish "$WORK/.env" "$TARGET"
  printf '\n設定完成，啟用插件：%s\n' "${PLUGINS[*]:-只有核心}"
  if [[ "$MODE" == server ]]; then
    printf '先準備資料目錄：sudo %q %q\n' "$SOURCE_ROOT/scripts/prepare-data.sh" "$DATA_DIR"
  fi
  printf '在包含 docker-compose.yml 的部署目錄執行：\n'
  printf 'cd %q\n' "$OUTPUT_ROOT/$MODE"
  printf 'docker compose config --quiet\ndocker compose up -d\n'
  printf '切換插件請重建對應容器；應用的 label / log 格式仍須自行設定。\n'
fi
