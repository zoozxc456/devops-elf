#!/usr/bin/env bash
# 在隔離暫存目錄檢查範例，不讀取個人 .env、secrets 或資料，也不啟動部署服務。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
python3 "$root/scripts/version.py" check
work=$(mktemp -d "${TMPDIR:-/tmp}/lookout-check.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/server" "$work/agent/alloy" "$work/tests"
cp "$root/server/docker-compose.yml" "$work/server/"
cp "$root/server/.env.example" "$work/server/.env"
cp -R "$root/server/prometheus" "$root/server/loki" "$root/server/alertmanager" "$root/server/grafana" "$work/server/"
mkdir -p "$work/server/secrets"
cp "$root/agent/docker-compose.yml" "$work/agent/"
cp "$root/agent/.env.example" "$work/agent/.env"
cp "$root/agent/alloy/config.alloy" "$root/agent/alloy/modules.alloy" "$work/agent/alloy/"
cp "$root/tests/alerts.test.yml" "$work/tests/"
python3 "$root/scripts/plugins.py" apply --output "$work" "$@"
cp "$work/agent/generated/log-pipeline.alloy" "$work/agent/alloy/log-pipeline.alloy"
# validate /etc/alloy 的單一目錄也包含生成的 pipeline；Compose 則獨立掛載同一個檔案。

# 啟用所有 exporter 模組，以確保 declare 內部的設定亦通過驗證。
cat > "$work/agent/alloy/targets.alloy" <<'ALLOY'
lookout_postgres "check" {
  env        = "prod"
  instance   = "check-pg"
  dsn        = "postgresql://monitoring:check@localhost:5432/postgres?sslmode=disable"
  forward_to = [prometheus.relabel.gate.receiver]
}
lookout_mysql "check" {
  env        = "prod"
  instance   = "check-mysql"
  dsn        = "monitoring:check@(localhost:3306)/"
  forward_to = [prometheus.relabel.gate.receiver]
}
lookout_redis "check" {
  env        = "prod"
  instance   = "check-redis"
  dsn        = "redis://localhost:6379"
  forward_to = [prometheus.relabel.gate.receiver]
}
ALLOY
for component in server agent; do
  docker compose --project-directory "$work/$component" config --quiet
  docker compose --project-directory "$work/$component" config --format json > "$work/$component.json"
done
image_for() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["services"][sys.argv[2]]["image"])' "$work/$1.json" "$2"
}
docker run --rm -e HOST_NAME=check -e HOST_ROLE=prod -e LOOKOUT_ENVS=prod -e APP_NETWORK=app \
  -e LOKI_PUSH_URL=http://localhost:3100/loki/api/v1/push \
  -e PROMETHEUS_REMOTE_WRITE_URL=http://localhost:9090/api/v1/write \
  -v "$work/agent/alloy:/etc/alloy:ro" "$(image_for agent alloy)" validate /etc/alloy
docker run --rm --entrypoint /bin/promtool -v "$work/server/prometheus:/etc/prometheus:ro" \
  "$(image_for server prometheus)" check config /etc/prometheus/prometheus.yml
# Mount only the readable test/rule directories. The mktemp root is 0700,
# which prevents the image's non-root user from traversing a whole-tree mount.
docker run --rm --entrypoint /bin/promtool \
  -v "$work/tests:/work/tests:ro" \
  -v "$work/server/prometheus/rules:/work/server/prometheus/rules:ro" \
  -w /work/tests "$(image_for server prometheus)" test rules /work/tests/alerts.test.yml
docker run --rm --entrypoint /bin/amtool -v "$work/server/alertmanager:/etc/alertmanager:ro" \
  "$(image_for server alertmanager)" check-config /etc/alertmanager/alertmanager.yml
docker run --rm -e LOKI_RETENTION=720h -e LOKI_RETENTION_NONPROD=168h \
  -v "$work/server/loki:/etc/loki:ro" -v "$work/server/generated/loki-rules:/etc/loki/rules:ro" "$(image_for server loki)" \
  -config.file=/etc/loki/loki.yml -config.expand-env=true -verify-config=true
python3 - "$work/server/generated/dashboards" <<'PY'
import json, pathlib, sys
uids = set()
for path in pathlib.Path(sys.argv[1]).glob('*.json'):
    dashboard = json.loads(path.read_text())
    uid = dashboard['uid']
    assert uid not in uids, f'Duplicate dashboard UID: {uid}'
    uids.add(uid)
    assert 'odoo-server-' not in path.read_text(), f'Fixed container selector: {path}'
    assert 'odoo-postgres-' not in path.read_text(), f'Fixed container selector: {path}'
    assert '$compose_project' not in path.read_text(), f'Removed label selector: {path}'
print(f'{len(uids)} dashboards: JSON / UID / portable selectors OK')
PY
printf 'Lookout 設定與告警測試全部通過。\n'
