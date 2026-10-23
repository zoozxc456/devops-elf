# Nginx Plugin

**English** | [繁體中文](README.zh-TW.md)

Run `python3 scripts/plugins.py apply nginx` from `lookout/`, including any other plugins you want to keep, then follow the [plugin guide](../README.md). For Ansible, set `lookout_plugins: [nginx]`.

See [http.conf](config/http.conf) and [log-output.conf](config/log-output.conf) for examples, adapting include paths and domains to your Nginx setup.

Add `lookout.enable=true`, `lookout.format=nginx`, `lookout.service=nginx`, and the appropriate `lookout.env` to your Nginx container. Container names are customizable. Alloy reads stdout/stderr, so emit a JSON access log to `/dev/stdout`.

Add the following to the Nginx `http` block or a conf.d file loaded by it, defining the format before use:

```nginx
map $host $lookout_env {
    default prod;
    staging.example.com staging;
}
log_format lookout escape=json
    '{"env":"$lookout_env",'
    '"vhost":"$host",'
    '"method":"$request_method",'
    '"uri":"$uri",'
    '"status":$status,'
    '"bytes":$body_bytes_sent,'
    '"request_time":$request_time,'
    '"upstream_status":"$upstream_status",'
    '"upstream_response_time":"$upstream_response_time"}';
```

Add these directives to the `server` or `location` you want to monitor:

```nginx
access_log /dev/stdout lookout;
error_log /dev/stderr warn;
```

You can retain existing access/error logs written to files. Using `$uri` keeps query-string tokens out of the access log, but native Nginx error logs may still include full requests; sensitive environments require additional redaction. Alloy drops non-JSON access logs, so avoid also sending the default main format to stdout.

```bash
# Replace nginx with your container name.
docker exec nginx nginx -t
docker exec nginx nginx -s reload
docker logs --tail 5 nginx
```

For proxies serving multiple environments, `LOOKOUT_ENVS` must include both the container environment and all environments emitted by the map. Example Grafana Explore queries:

```logql
{format="nginx", service="nginx"}
{format="nginx", env="prod"} | status=~"5.."
{format="nginx", level=~"ERROR|CRITICAL|WARN"}
```

The Nginx dashboard and alerts query `format="nginx"` and support multiple proxies. Default alerts trigger for a 5xx rate above 5% with more than 20 requests in five minutes, or p95 latency above five seconds for ten minutes.
