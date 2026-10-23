#!/usr/bin/env bash
# 從 grafana.com 下載社群儀表板，把 ${DS_PROMETHEUS} 佔位換成固定的 datasource uid，
# 輸出到 server/grafana/dashboards/。更新版本時重跑一次再 commit。
set -euo pipefail

cd "$(dirname "$0")/.."
out=server/grafana/dashboards

fetch() {
  local id=$1 file=$2
  echo "下載 #$id → $out/$file"
  curl -fsSL "https://grafana.com/api/dashboards/$id/revisions/latest/download" \
    | python3 -I -c '
import json, sys
s = sys.stdin.read().replace("${DS_PROMETHEUS}", "prometheus")
d = json.loads(s)
d.pop("__inputs", None)
d.pop("__requires", None)
d["id"] = None
variables = d.get("templating", {}).get("list", [])
d.get("templating", {})["list"] = [v for v in variables if v.get("name") != "compose_project"]
for v in d.get("templating", {}).get("list", []):
    if v.get("type") == "datasource":
        v["current"] = {"text": "Prometheus", "value": "prometheus"}
def normalize(value):
    if isinstance(value, dict):
        return {key: normalize(item) for key, item in value.items()}
    if isinstance(value, list):
        return [normalize(item) for item in value]
    if isinstance(value, str):
        return value.replace(chr(44) + chr(32) + "container_label_com_docker_compose_project=~" + chr(34) + "$compose_project" + chr(34), "")
    return value
d = normalize(d)
json.dump(d, sys.stdout, ensure_ascii=False, indent=2)
' > "$out/$file"
}

fetch 1860  node-exporter-full.json   # 主機
fetch 19792 cadvisor.json             # 容器
fetch 14114 postgres.json             # Postgres（變數用 job=postgres / instance）
