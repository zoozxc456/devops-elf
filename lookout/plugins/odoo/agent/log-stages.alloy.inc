  // --------------------------------------------------------------------------
  // odoo：2026-10-22 05:12:33,123 7 INFO <db> <logger>: <message> <perf_info>
  // --------------------------------------------------------------------------
  stage.match {
    selector = "{format=\"odoo\"}"

    // traceback 的後續行沒有時間戳，併進上一筆
    stage.multiline {
      firstline     = "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2},\\d{3} "
      max_wait_time = "3s"
      max_lines     = 500
    }

    stage.regex {
      expression = "^\\S+ \\S+ \\d+ (?P<level>[A-Z]+) (?P<db>\\S+) (?P<logger>[^\\s:]+): "
    }

    // 多租戶時 db 數量可能很多，放 structured metadata 不放 label，避免 stream 數膨脹
    stage.structured_metadata {
      values = { db = "", logger = "" }
    }
  }

