#!/usr/bin/env bash
# 在 server/ 下執行，或傳入資料目錄的絕對路徑。僅建立四個服務目錄與權限。
set -euo pipefail
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo '請使用 sudo 執行以設定容器 UID/GID。' >&2
  exit 1
fi
root=${1:-"$(cd "$(dirname "$0")/../server" && pwd)/data"}
if [[ "$root" != /* || "$root" == / ]]; then
  echo '資料目錄須為非根目錄的絕對路徑。' >&2
  exit 1
fi
for entry in prometheus:65534:65534 alertmanager:65534:65534 loki:10001:10001 grafana:472:0; do
  IFS=: read -r name uid gid <<< "$entry"
  mkdir -p "$root/$name"
  chown "$uid:$gid" "$root/$name"
  chmod 750 "$root/$name"
done
printf '資料目錄已就緒：%s\n' "$root"
