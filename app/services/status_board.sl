# Everything a status page shows, computed once: components grouped with
# their live status and 90-day bars, the overall banner, open incidents,
# maintenance, history. The HTML page, the JSON API and the badges all read
# this, so they never disagree.
const STATUS_SEVERITY = {
  "down": 4,
  "degraded": 3,
  "maintenance": 2,
  "up": 1,
  "pending": 0
}
const HISTORY_DAYS = 90
# Failed checks closer than this (on top of the monitor's interval) belong to
# the same disruption.
const DISRUPTION_GAP_S = 120
const DISRUPTION_LIMIT = 30

class StatusBoard
  static def build(page, now)
    components = page.components
    monitor_ids = components.map do |component|
      component.monitor_ids
    end.flatten.uniq
    monitors = []
    maintenances = []
    open_incidents = []
    history = []
    failures = []
    grouped(fn() {
      monitors = Monitor.where("doc._key IN @ids", {"ids": monitor_ids}).all
      maintenances = Maintenance.where(
        "doc.ends_at > @now AND doc.starts_at < @horizon AND LENGTH(INTERSECTION(doc.monitor_ids, @ids)) > 0",
        {
          "now": now,
          "horizon": now + 7 * 86400,
          "ids": monitor_ids
        }
      ).order("starts_at").all
      open_incidents = Incident.where(
        "doc.status != 'resolved' AND LENGTH(INTERSECTION(doc.monitor_ids, @ids)) > 0",
        {"ids": monitor_ids}
      ).order("started_at", "desc").all
      history = Incident.where(
        "doc.status == 'resolved' AND doc.started_at >= @since AND LENGTH(INTERSECTION(doc.monitor_ids, @ids)) > 0",
        {"since": now - HISTORY_DAYS * 86400, "ids": monitor_ids}
      ).order("started_at", "desc").limit(20).all
      failures = Check.where(
        "doc.monitor_id IN @ids AND doc.status == 'down' AND doc.maintenance != true AND doc.at >= @since",
        {"ids": monitor_ids, "since": now - Rollup.retention_days * 86400}
      ).order("at").limit(2000).all
    })
    today = Checker.day_of(now)
    board_context = {
      "now": now,
      "monitors": monitors.index_by("_key"),
      "maintenance_ids": maintenances.filter do |window|
        window.active_at?(now)
      end.map do |window|
        window.monitor_ids
      end.flatten.uniq,
      "open_incidents": open_incidents,
      "windows": Uptime.windows(monitor_ids, today),
      "last_day": Uptime.last_day(monitor_ids, now),
      "daily": Uptime.daily(monitor_ids, today).group_by("monitor_id"),
      "today": today
    }
    rows = components.map do |component|
      StatusBoard.component_row(component, board_context)
    end
    {
      "page": page,
      "status": StatusBoard.overall(rows),
      "groups": StatusBoard.group_rows(rows),
      "components": rows,
      "open_incidents": open_incidents.map do |incident|
        StatusBoard.incident_row(incident, board_context)
      end,
      "maintenances": maintenances.map do |window|
        StatusBoard.maintenance_row(window, now)
      end,
      "history": history.map do |incident|
        StatusBoard.incident_row(incident, board_context)
      end,
      "disruptions": StatusBoard.disruptions(
        failures,
        components,
        board_context["monitors"],
        open_incidents + history,
        now
      ),
      "generated_at": now
    }
  end

  # What the landing page says of a page: its overall state, how many
  # services it shows, and their mean availability over 30 days.
  static def summary(page, now)
    board = StatusBoard.build(page, now)
    figures = board["components"].map do |row|
      row["uptime"]["30d"]
    end.compact
    {
      "title": page.title,
      "slug": page.slug,
      "description": page.description,
      "status": board["status"],
      "services": board["components"].length,
      "incidents": board["open_incidents"].length,
      "uptime_30d": figures.length > 0 ? figures.sum / figures.length : nil
    }
  end

  static def component_row(component, board_context)
    statuses = component.monitor_ids.map do |monitor_id|
      StatusBoard.monitor_status(monitor_id, board_context)
    end.compact
    board_context["open_incidents"].each do |incident|
      touches = incident.monitor_ids.any? do |monitor_id|
        component.monitor_ids.includes?(monitor_id)
      end
      statuses.push(incident.impact == "degraded" ? "degraded" : "down") if touches
    end
    status = StatusBoard.worst(statuses)
    daily_rows = component.monitor_ids.map do |monitor_id|
      board_context["daily"][monitor_id] ?? []
    end.flatten
    {
      "name": component.name,
      "url": StatusBoard.site_url(component, board_context),
      "slug": component.slug,
      "description": component.description,
      "group": component.group_name,
      "status": status,
      "status_label": StatusBoard.status_label(status),
      "uptime": StatusBoard.uptime_figures(component.monitor_ids, board_context),
      "bars": Uptime.bars(daily_rows, board_context["today"])
    }
  end

  # nil for a paused or deleted monitor: it does not speak for its component.
  # The address a visitor can open for a component: the URL of its first HTTP
  # monitor, or nil when it has none (a heartbeat, a certificate alone).
  static def site_url(component, board_context)
    http = component.monitor_ids.map do |monitor_id|
      board_context["monitors"][monitor_id]
    end.compact.find do |monitor|
      monitor.kind == "http" && monitor.url.to_s.starts_with("http")
    end
    http&.url
  end

  static def monitor_status(monitor_id, board_context)
    monitor = board_context["monitors"][monitor_id]
    return nil if monitor.nil? || monitor.paused
    return "maintenance" if board_context["maintenance_ids"].includes?(monitor_id)

    monitor.status
  end

  static def uptime_figures(monitor_ids, board_context)
    totals = {
      "t1": 0,
      "u1": 0,
      "t7": 0,
      "u7": 0,
      "t30": 0,
      "u30": 0,
      "t90": 0,
      "u90": 0
    }
    monitor_ids.each do |monitor_id|
      windows = board_context["windows"][monitor_id] ?? {}
      last_day = board_context["last_day"][monitor_id] ?? {}
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

    statuses.sort_by do |status|
      -(STATUS_SEVERITY[status] ?? 0)
    end.first
  end

  static def overall(rows)
    statuses = rows.map do |row|
      row["status"]
    end.filter do |status|
      status != "pending"
    end
    down = statuses.filter do |status|
      status == "down"
    end.length
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
    names = rows.map do |row|
      row["group"].to_s
    end.uniq
    names.map do |name|
      {"name": name, "components": rows.filter do |row|
        row["group"].to_s == name
      end}
    end
  end

  # What made a day "Perturbations" without an incident: the failed checks of
  # each monitor, grouped into episodes (failures less than an interval plus
  # DISRUPTION_GAP_S apart), newest first. An episode an incident already
  # tells about is left out.
  # -> [{"services", "monitor", "started_at", "duration", "checks", "error"}]
  static def disruptions(failures, components, monitors_by_key, incidents, now)
    episodes = []
    failures.group_by("monitor_id").each do |monitor_id, checks|
      monitor = monitors_by_key[monitor_id]
      next if monitor.nil?

      gap = monitor.interval_s.to_i + DISRUPTION_GAP_S
      current = nil
      checks.sort_by(&:at).each do |check|
        if !current.nil? && check.at - current["last"] <= gap
          current["last"] = check.at
          current["checks"] = current["checks"] + 1
        else
          episodes.push(current) unless current.nil?
          current = {
            "monitor": monitor,
            "started_at": check.at,
            "last": check.at,
            "checks": 1,
            "error": check.error
          }
        end
      end
      episodes.push(current) unless current.nil?
    end
    rows = episodes.filter do |episode|
      !StatusBoard.told_by_incident?(episode, incidents, now)
    end.map do |episode|
      monitor = episode["monitor"]
      services = components.filter do |component|
        component.monitor_ids.includes?(monitor._key)
      end.map(&:name)
      {
        "services": services.length > 0 ? services : [monitor.name],
        "started_at": episode["started_at"],
        "seconds": episode["last"] - episode["started_at"] + monitor.interval_s.to_i,
        "checks": episode["checks"],
        "error": Probe.describe_error(episode["error"].to_s, monitor.timeout_s ?? 10)
      }
    end
    StatusBoard.merge_simultaneous(rows).sort_by do |row|
      -row["started_at"]
    end.take(DISRUPTION_LIMIT).map do |row|
      row.merge({"duration": Probe.duration_label(row["seconds"])})
    end
  end

  # Several services failing within the same DISRUPTION_GAP_S for the same
  # reason are one event (often the network of Vigie itself): one row naming
  # them all, not one row each.
  static def merge_simultaneous(rows)
    merged = []
    rows.sort_by(&:started_at).each do |row|
      twin = merged.find do |kept|
        kept["error"] == row["error"] && (row["started_at"] - kept["started_at"]).abs <= DISRUPTION_GAP_S
      end
      if twin.nil?
        merged.push(row.merge({}))
      else
        twin["services"] = (twin["services"] + row["services"]).uniq
        twin["checks"] = twin["checks"] + row["checks"]
        twin["seconds"] = [twin["seconds"], row["seconds"]].max
      end
    end
    merged
  end

  static def told_by_incident?(episode, incidents, now)
    incidents.any? do |incident|
      incident.monitor_ids.includes?(episode["monitor"]._key) &&
          episode["started_at"] >= incident.started_at.to_i - DISRUPTION_GAP_S &&
          episode["started_at"] <= (incident.resolved_at ?? now).to_i + DISRUPTION_GAP_S
    end
  end

  static def incident_row(incident, board_context)
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
      "updates": incident.updates.map do |update|
        {
          "status": update.status,
          "status_label": update.status_label,
          "message": update.message,
          "at": update.at
        }
      end
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
      _ => "En attente",
    }
  end
end
