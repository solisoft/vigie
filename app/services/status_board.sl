# Everything a status page shows, computed once: components grouped with
# their live status and 90-day bars, the overall banner, open incidents,
# maintenance, history. The HTML page, the JSON API and the badges all read
# this, so they never disagree.
const STATUS_SEVERITY = {"down": 4, "degraded": 3, "maintenance": 2, "up": 1, "pending": 0}
const HISTORY_DAYS = 90

class StatusBoard
  static def build(page, now)
    components = page.components
    monitor_ids = components.map { |component| component.monitor_ids }.flatten.uniq
    monitors = []
    maintenances = []
    open_incidents = []
    history = []
    grouped(fn() {
      monitors = Monitor.where("doc._key IN @ids", {"ids": monitor_ids}).all
      maintenances = Maintenance.where("doc.ends_at > @now AND doc.starts_at < @horizon AND LENGTH(INTERSECTION(doc.monitor_ids, @ids)) > 0", {"now": now, "horizon": now + 7 * 86400, "ids": monitor_ids}).order("starts_at").all
      open_incidents = Incident.where("doc.status != 'resolved' AND LENGTH(INTERSECTION(doc.monitor_ids, @ids)) > 0", {"ids": monitor_ids}).order("started_at", "desc").all
      history = Incident.where("doc.status == 'resolved' AND doc.started_at >= @since AND LENGTH(INTERSECTION(doc.monitor_ids, @ids)) > 0", {"since": now - HISTORY_DAYS * 86400, "ids": monitor_ids}).order("started_at", "desc").limit(20).all
    })
    today = Checker.day_of(now)
    context = {
      "now": now,
      "monitors": monitors.index_by("_key"),
      "maintenance_ids": maintenances.filter { |window| window.active_at?(now) }.map { |window| window.monitor_ids }.flatten.uniq,
      "open_incidents": open_incidents,
      "windows": Uptime.windows(monitor_ids, today),
      "last_day": Uptime.last_day(monitor_ids, now),
      "daily": Uptime.daily(monitor_ids, today).group_by("monitor_id"),
      "today": today
    }
    rows = components.map { |component| StatusBoard.component_row(component, context) }
    {
      "page": page,
      "status": StatusBoard.overall(rows),
      "groups": StatusBoard.group_rows(rows),
      "components": rows,
      "open_incidents": open_incidents.map { |incident| StatusBoard.incident_row(incident, context) },
      "maintenances": maintenances.map { |window| StatusBoard.maintenance_row(window, now) },
      "history": history.map { |incident| StatusBoard.incident_row(incident, context) },
      "generated_at": now
    }
  end

  static def component_row(component, context)
    statuses = component.monitor_ids.map { |monitor_id| StatusBoard.monitor_status(monitor_id, context) }.compact
    context["open_incidents"].each do |incident|
      touches = incident.monitor_ids.any? { |monitor_id| component.monitor_ids.includes?(monitor_id) }
      statuses.push(incident.impact == "degraded" ? "degraded" : "down") if touches
    end
    status = StatusBoard.worst(statuses)
    daily_rows = component.monitor_ids.map { |monitor_id| context["daily"][monitor_id] ?? [] }.flatten
    {
      "name": component.name,
      "slug": component.slug,
      "description": component.description,
      "group": component.group_name,
      "status": status,
      "status_label": StatusBoard.status_label(status),
      "uptime": StatusBoard.uptime_figures(component.monitor_ids, context),
      "bars": Uptime.bars(daily_rows, context["today"])
    }
  end

  # nil for a paused or deleted monitor: it does not speak for its component.
  static def monitor_status(monitor_id, context)
    monitor = context["monitors"][monitor_id]
    return nil if monitor.nil? || monitor.paused
    return "maintenance" if context["maintenance_ids"].includes?(monitor_id)

    monitor.status
  end

  static def uptime_figures(monitor_ids, context)
    totals = {"t1": 0, "u1": 0, "t7": 0, "u7": 0, "t30": 0, "u30": 0, "t90": 0, "u90": 0}
    monitor_ids.each do |monitor_id|
      windows = context["windows"][monitor_id] ?? {}
      last_day = context["last_day"][monitor_id] ?? {}
      totals["t1"] = totals["t1"] + last_day["total"].to_i
      totals["u1"] = totals["u1"] + last_day["up"].to_i
      ["7", "30", "90"].each do |span|
        totals["t#{span}"] = totals["t#{span}"] + windows["t#{span}"].to_i
        totals["u#{span}"] = totals["u#{span}"] + windows["u#{span}"].to_i
      end
    end
    {
      "24h": Uptime.percent(totals["u1"], totals["t1"]),
      "7d": Uptime.percent(totals["u7"], totals["t7"]),
      "30d": Uptime.percent(totals["u30"], totals["t30"]),
      "90d": Uptime.percent(totals["u90"], totals["t90"])
    }
  end

  static def worst(statuses)
    return "pending" if statuses.length == 0

    statuses.sort_by { |status| -(STATUS_SEVERITY[status] ?? 0) }.first
  end

  static def overall(rows)
    statuses = rows.map { |row| row["status"] }.filter { |status| status != "pending" }
    down = statuses.filter { |status| status == "down" }.length
    return StatusBoard.banner("major", "Panne générale") if down > 0 && down == statuses.length
    return StatusBoard.banner("partial", "Panne partielle : certains services sont indisponibles") if down > 0
    return StatusBoard.banner("degraded", "Performances dégradées") if statuses.includes?("degraded")
    return StatusBoard.banner("maintenance", "Maintenance en cours") if statuses.includes?("maintenance")
    return StatusBoard.banner("pending", "Surveillance en cours de démarrage") if statuses.length == 0

    StatusBoard.banner("ok", "Tous les systèmes sont opérationnels")
  end

  static def banner(level, label)
    {"level": level, "label": label}
  end

  static def group_rows(rows)
    names = rows.map { |row| row["group"].to_s }.uniq
    names.map { |name| {"name": name, "components": rows.filter { |row| row["group"].to_s == name }} }
  end

  static def incident_row(incident, context)
    {
      "id": incident._key,
      "title": incident.title,
      "status": incident.status,
      "status_label": incident.status_label,
      "impact": incident.impact,
      "impact_label": incident.impact_label,
      "kind": incident.kind,
      "started_at": incident.started_at,
      "resolved_at": incident.resolved_at,
      "duration": incident.resolved_at.nil? ? nil : Probe.duration_label(incident.resolved_at - incident.started_at),
      "updates": incident.updates.map { |update| {"status": update.status, "status_label": update.status_label, "message": update.message, "at": update.at} }
    }
  end

  static def maintenance_row(window, now)
    {
      "id": window._key,
      "title": window.title,
      "description": window.description,
      "starts_at": window.starts_at,
      "ends_at": window.ends_at,
      "active": window.active_at?(now)
    }
  end

  static def status_label(status)
    match status {
      "up" => "Opérationnel",
      "degraded" => "Dégradé",
      "down" => "Panne",
      "maintenance" => "Maintenance",
      _ => "En attente"
    }
  end
end
