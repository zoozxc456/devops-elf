  // --------------------------------------------------------------------------
  // nginx：JSON access log（log_format lookout，見 plugins/nginx/README.md）+ 原生 error log
  // --------------------------------------------------------------------------

  // 只收 JSON access log 與 nginx error log，其餘一律丟掉。
  // 例如預設的 main 格式：它記完整 $request（含 query string 的 token）
  stage.match {
    selector = "{format=\"nginx\"} !~ \"^(\\\\{|\\\\d{4}/\\\\d{2}/\\\\d{2} )\""
    action   = "drop"
  }

  // access log：{"env":"prod","vhost":"...","status":502,"request_time":1.234,...}
  stage.match {
    selector = "{format=\"nginx\"} |~ \"^\\\\{\""

    stage.json {
      expressions = { env = "", vhost = "", status = "" }
    }

    // 一台 nginx 代理多個環境時，env 由 nginx 依網域寫進每一行；沒寫就沿用容器的 env
    stage.labels {
      values = { env = "" }
    }

    // vhost、status 放 structured metadata：查詢時可直接 | status=~"5.."，不必每次 | json
    stage.structured_metadata {
      values = { vhost = "", status = "" }
    }
  }

  // error log：2026/10/22 05:12:33 [error] 29#29: *1 connect() failed ...
  stage.match {
    selector = "{format=\"nginx\"} |~ \"^\\\\d{4}/\\\\d{2}/\\\\d{2} \""

    stage.regex {
      expression = "^\\S+ \\S+ \\[(?P<level>[a-z]+)\\]"
    }
  }

