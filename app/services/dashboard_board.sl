# The admin dashboard: every monitor with its live state, uptime, latency
# percentiles and a sparkline of the last 6 hours. Four reads in total.
class DashboardBoard
  static def build(now)
    monitors = Monitor.order("name").all
    ids = monitors.map { |monitor| monitor._key }
    today = Checker.day_of(now)
    maintenance_ids = Maintenance.active_at(now).map { |window| window.monitor_ids }.flatten.uniq
    last_day = Uptime.last_day(ids, now)
    windows = Uptime.windows(ids, today)
    recent = Sparkline.recent(ids, now, 6)
    rows = monitors.map do |monitor|
      DashboardBoard.row(monitor, maintenance_ids, last_day[monitor._key] ?? {}, windows[monitor._key] ?? {}, recent[monitor._key] ?? [])
    end
    {
      "rows": rows,
      "counts": DashboardBoard.counts(rows),
      "open_incidents": Incident.open_all.length
    }
  end

  static def row(monitor, maintenance_ids, last_day, windows, points)
    status = DashboardBoard.effective_status(monitor, maintenance_ids)
    {
      "id": monitor._key,
      "name": monitor.name,
      "kind": monitor.kind_label,
      "target": monitor.target_label,
      "status": status,
      "error": monitor.last_error,
      "latency_ms": monitor.last_latency_ms,
      "checked_at": monitor.last_checked_at,
      "tls_days_left": monitor.tls_days_left,
      "uptime_24h": Uptime.percent(last_day["up"], last_day["total"]),
      "uptime_30d": Uptime.percent(windows["u30"], windows["t30"]),
      "p50_ms": last_day["p50_ms"],
      "p95_ms": last_day["p95_ms"],
      "spark": Sparkline.svg(points.drop([points.length - 40, 0].max), "Latence de #{monitor.name} sur 6 h")
    }
  end

  static def effective_status(monitor, maintenance_ids)
    return "paused" if monitor.paused
    return "maintenance" if maintenance_ids.includes?(monitor._key)

    monitor.status
  end

  static def counts(rows)
    tally = {"up": 0, "degraded": 0, "down": 0, "other": 0}
    rows.each do |row|
      bucket = ["up", "degraded", "down"].includes?(row["status"]) ? row["status"] : "other"
      tally[bucket] = tally[bucket] + 1
    end
    tally
  end
end
