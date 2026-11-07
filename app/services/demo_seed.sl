# The demo: a status page with monitors on public targets and 90 days of
# synthetic history, so the bars look alive on the first run. Idempotent:
# a second run keeps what exists and only rewrites the synthetic rollups.
const DEMO_SLUG = "demo"
const DEMO_EMAIL = "demo@vigie.example"
const DEMO_PASSWORD = "vigie-demo-2026"

class DemoSeed
  static def run(now)
    user = DemoSeed.admin
    monitors = DemoSeed.monitors
    page = DemoSeed.page(monitors)
    history = DemoSeed.history(monitors, now)
    DemoSeed.maintenance(monitors, now)
    DemoSeed.channels
    {"user": user.email, "page": page.slug, "monitors": monitors.length, "rollups": history["rollups"], "checks": history["checks"]}
  end

  static def admin
    existing = User.find_by("email", DEMO_EMAIL)
    return existing unless existing.nil?

    user = User.new()
    user.email = DEMO_EMAIL
    user.set_password(getenv("VIGIE_DEMO_PASSWORD") || DEMO_PASSWORD)
    user.save
    user
  end

  static def monitors
    definitions = [
      {"name": "Site Soli", "kind": "http", "url": "https://soli.solisoft.net", "keyword": "Soli", "interval_s": 60, "degraded_ms": 1500},
      {"name": "Example.com", "kind": "http", "url": "https://example.com", "keyword": "Example Domain", "interval_s": 60},
      {"name": "Certificat soli.solisoft.net", "kind": "tls", "host": "soli.solisoft.net", "port": 443, "interval_s": 3600, "tls_warn_days": 14},
      {"name": "Sauvegarde nocturne", "kind": "heartbeat", "interval_s": 3600, "grace_s": 600}
    ]
    if TargetGuard.allow_private?
      self_url = (getenv("APP_URL") || "http://127.0.0.1:5099").delete_suffix("/").replace("localhost", "127.0.0.1")
      definitions.push({"name": "Vigie elle-même", "kind": "http", "url": "#{self_url}/health", "keyword": "ok", "interval_s": 30})
    end
    definitions.map do |definition|
      Monitor.find_by("name", definition["name"]) ?? DemoSeed.create_monitor(definition)
    end
  end

  # A heartbeat starts as just pinged, so the demo is green until the cron
  # (see the README) takes over.
  static def create_monitor(definition)
    definition["last_heartbeat_at"] = DateTime.utc.to_unix if definition["kind"] == "heartbeat"
    Monitor.create(definition)
  end

  static def page(monitors)
    page = StatusPage.find_by("slug", DEMO_SLUG)
    return page unless page.nil?

    page = StatusPage.create({
      "slug": DEMO_SLUG,
      "title": "Solisoft",
      "description": "État des services, mis à jour en direct",
      "published": true
    })
    by_name = monitors.index_by("name")
    layout = [
      ["Web", "Site Soli", "soli.solisoft.net, et son certificat TLS", ["Site Soli", "Certificat soli.solisoft.net"]],
      ["Web", "Example.com", "Un voisin de confiance", ["Example.com"]],
      ["Tâches planifiées", "Sauvegarde nocturne", "Le cron envoie un battement à chaque passage", ["Sauvegarde nocturne"]]
    ]
    layout.push(["Plateforme", "Vigie", "Cette instance, surveillée par elle-même", ["Vigie elle-même"]]) unless by_name["Vigie elle-même"].nil?
    layout.each_with_index do |entry, position|
      ids = entry[3].map { |name| by_name[name]&._key }.compact
      Component.create({"page_id": page._key, "group_name": entry[0], "name": entry[1], "description": entry[2], "position": position, "monitor_ids": ids})
    end
    page
  end

  # 89 past days of rollups (with a few bad days and their incidents), then
  # the last 6 hours of raw checks every 5 minutes.
  static def history(monitors, now)
    today = Checker.day_of(now)
    rollups = 0
    monitors.each_with_index do |monitor, index|
      per_day = 86400 / monitor.interval_s
      (1..90).each do |days_ago|
        day = Uptime.days_back(today, days_ago)
        figures = DemoSeed.synthetic_day(per_day, days_ago, index)
        DailyRollup.upsert("#{monitor._key}_#{day}", {"monitor_id": monitor._key, "day": day}.merge(figures))
        rollups = rollups + 1
      end
    end
    DemoSeed.incidents(monitors, now)
    checks = DemoSeed.recent_checks(monitors, now)
    Rollup.recompute(now)
    {"rollups": rollups, "checks": checks}
  end

  # Deterministic: the same days are bad on every run.
  static def synthetic_day(per_day, days_ago, index)
    latency = 80 + (days_ago * 37 + index * 11) % 60
    figures = {"total": per_day, "up": per_day, "maintenance": 0, "p50_ms": latency, "p95_ms": latency * 2 + 40}
    if days_ago == 12 && index == 0
      figures["up"] = per_day - per_day / 20
    elsif days_ago == 37 && index == 1
      figures["up"] = per_day - per_day / 120
    elsif days_ago == 64 && index == 0
      figures = figures.merge({"total": per_day - per_day / 12, "up": per_day - per_day / 12, "maintenance": per_day / 12})
    elsif days_ago == 21 && index == 3
      figures["up"] = per_day - 2
    end
    figures
  end

  static def incidents(monitors, now)
    return nil if Incident.where({"kind": "auto"}).count > 0

    DemoSeed.past_incident(monitors[0], now - 12 * 86400 + 3600 * 9, 72 * 60, "HTTP 502 (attendu 200–399)")
    DemoSeed.past_incident(monitors[1], now - 37 * 86400 + 3600 * 15, 12 * 60, "Délai dépassé (10 s)")
    DemoSeed.past_incident(monitors[3], now - 21 * 86400 + 3600 * 4, 2 * 3600, "Aucun ping reçu depuis 70 min")
  end

  static def past_incident(monitor, started_at, duration, error)
    incident = Incident.create({
      "title": "#{monitor.name} est indisponible",
      "kind": "auto",
      "status": "resolved",
      "impact": "outage",
      "monitor_ids": [monitor._key],
      "started_at": started_at,
      "resolved_at": started_at + duration
    })
    IncidentUpdate.create({"incident_id": incident._key, "status": "investigating", "message": "Vigie a constaté 2 échecs consécutifs : #{error}", "at": started_at})
    IncidentUpdate.create({"incident_id": incident._key, "status": "identified", "message": "Cause identifiée côté hébergeur, correctif en cours de déploiement.", "at": started_at + duration / 3})
    IncidentUpdate.create({"incident_id": incident._key, "status": "resolved", "message": "Le service répond de nouveau. Durée de l'incident : #{Probe.duration_label(duration)}.", "at": started_at + duration})
    incident
  end

  static def recent_checks(monitors, now)
    rows = []
    monitors.each_with_index do |monitor, index|
      next if monitor.kind == "heartbeat"

      (0..72).each do |step|
        at = now - (72 - step) * 300
        latency = 90 + (step * 53 + index * 17) % 140
        rows.push({"monitor_id": monitor._key, "at": at, "day": Checker.day_of(at), "status": "up", "ok": true, "latency_ms": latency, "http_status": monitor.kind == "http" ? 200 : nil, "error": nil, "maintenance": false})
      end
    end
    return 0 if Check.where("doc.at >= @since", {"since": now - 6 * 3600}).count > 0

    Check.create_many(rows)
    rows.length
  end

  static def maintenance(monitors, now)
    return nil if Maintenance.count > 0

    backup = monitors.find { |monitor| monitor.kind == "heartbeat" }
    tomorrow = DateTime.parse(Uptime.days_back(Checker.day_of(now), -1)).to_unix
    Maintenance.create({
      "title": "Migration du serveur de sauvegarde",
      "description": "Les sauvegardes peuvent manquer un passage pendant la bascule.",
      "starts_at": tomorrow + 2 * 3600,
      "ends_at": tomorrow + 3 * 3600,
      "monitor_ids": [backup._key]
    })
  end

  static def channels
    return nil if AlertChannel.count > 0

    AlertChannel.create({"name": "Astreinte (exemple)", "kind": "email", "target": "astreinte@vigie.example", "active": false})
    AlertChannel.create({"name": "Slack #ops (exemple)", "kind": "slack", "target": "https://hooks.slack.com/services/T000/B000/XXXX", "active": false})
  end
end
