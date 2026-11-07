board_page = nil
board_api = nil
board_web = nil

def board_reset
  [Check, DailyRollup, Incident, IncidentUpdate, Maintenance, Component, StatusPage, Monitor].each do |model|
    model.all.each do |record|
      record.delete
    end
  end
  board_api = Monitor.create({
    "name": "API",
    "url": "https://api.example.com",
    "status": "up"
  })
  board_web = Monitor.create({
    "name": "Web",
    "url": "https://www.example.com",
    "status": "up"
  })
  board_page = StatusPage.create({
    "title": "Acme",
    "slug": "acme"
  })
  Component.create({
    "page_id": board_page._key,
    "name": "API",
    "group_name": "Plateforme",
    "position": 1,
    "monitor_ids": [board_api._key]
  })
  Component.create({
    "page_id": board_page._key,
    "name": "Web",
    "group_name": "",
    "position": 0,
    "monitor_ids": [board_web._key]
  })
end

def board_set(monitor, status)
  monitor.status = status
  monitor.save
end

describe("StatusBoard") do
  before_each() do
    board_reset()
  end

  test("all up: the green banner, groups in order") do
    board = StatusBoard.build(board_page, DateTime.utc.to_unix)
    assert_eq(board["status"]["level"], "ok")
    assert_eq(board["groups"].map(&{ |group|
      group["name"]
    }), ["", "Plateforme"])
    assert_eq(board["components"][0]["bars"].length, 90)
  end

  test("summary: the overall state, the count of services, open incidents") do
    summary = StatusBoard.summary(board_page, DateTime.utc.to_unix)
    assert_eq(summary["slug"], board_page.slug)
    assert_eq(summary["status"]["level"], "ok")
    assert_eq(summary["services"], StatusBoard.build(board_page, DateTime.utc.to_unix)["components"].length)
    assert_eq(summary["incidents"], 0)
  end

  test("a component links to its HTTP monitor's address; a heartbeat has none") do
    beat = Monitor.create({
      "name": "Cron",
      "kind": "heartbeat",
      "interval_s": 3600
    })
    Component.create({
      "page_id": board_page._key,
      "name": "Cron",
      "group_name": "",
      "position": 2,
      "monitor_ids": [beat._key]
    })
    by_name = StatusBoard.build(board_page, DateTime.utc.to_unix)["components"].index_by("name")
    assert_eq(by_name["Web"]["url"], "https://www.example.com")
    assert_eq(by_name["API"]["url"], "https://api.example.com")
    assert_null(by_name["Cron"]["url"])
  end

  test("one down out of two is a partial outage; all down is major") do
    board_set(board_api, "down")
    assert_eq(StatusBoard.build(board_page, DateTime.utc.to_unix)["status"]["level"], "partial")
    board_set(board_web, "down")
    assert_eq(StatusBoard.build(board_page, DateTime.utc.to_unix)["status"]["label"], "Panne générale")
  end

  test("degraded and maintenance have their own banners") do
    board_set(board_api, "degraded")
    assert_eq(StatusBoard.build(board_page, DateTime.utc.to_unix)["status"]["level"], "degraded")
    board_set(board_api, "up")
    now = DateTime.utc.to_unix
    Maintenance.create({
      "title": "Fenêtre",
      "starts_at": now - 10,
      "ends_at": now + 100,
      "monitor_ids": [board_api._key]
    })
    board = StatusBoard.build(board_page, now)
    assert_eq(board["status"]["level"], "maintenance")
    assert_eq(board["maintenances"][0]["active"], true)
  end

  test("a paused monitor does not speak; no data at all is pending") do
    board_api.paused = true
    board_api.save
    board_set(board_web, "pending")
    board = StatusBoard.build(board_page, DateTime.utc.to_unix)
    assert_eq(board["status"]["level"], "pending")
    assert_eq(board["components"].find(&{ |row|
      row["name"] == "API"
    })["status"], "pending")
  end

  test("an open manual incident colours its components by impact") do
    Incident.create({
      "title": "Lenteurs",
      "impact": "degraded",
      "monitor_ids": [board_web._key]
    })
    board = StatusBoard.build(board_page, DateTime.utc.to_unix)
    assert_eq(board["components"].find(&{ |row|
      row["name"] == "Web"
    })["status"], "degraded")
    assert_eq(board["open_incidents"].length, 1)
  end

  test("history holds the incidents resolved in the last 90 days") do
    now = DateTime.utc.to_unix
    Incident.create({
      "title": "Vieux",
      "status": "resolved",
      "monitor_ids": [board_api._key],
      "started_at": now - 100 * 86400,
      "resolved_at": now - 100 * 86400 + 60
    })
    Incident.create({
      "title": "Récent",
      "status": "resolved",
      "monitor_ids": [board_api._key],
      "started_at": now - 3600,
      "resolved_at": now - 1800
    })
    history = StatusBoard.build(board_page, now)["history"]
    assert_eq(history.map(&{ |row|
      row["title"]
    }), ["Récent"])
    assert_eq(history[0]["duration"], "30 min")
  end

  test("worst status wins") do
    assert_eq(StatusBoard.worst([
      "up",
      "maintenance",
      "degraded"
    ]), "degraded")
    assert_eq(StatusBoard.worst([]), "pending")
    assert_eq(StatusBoard.status_label("maintenance"), "Maintenance")
    assert_eq(StatusBoard.status_label("whatever"), "En attente")
  end
end

describe("DashboardBoard") do
  before_each() do
    board_reset()
  end

  test("counts monitors by state and draws sparklines") do
    board_set(board_api, "down")
    now = DateTime.utc.to_unix
    [120, 340, 90].each_with_index do |latency, i|
      Check.create({
        "monitor_id": board_web._key,
        "at": now - 300 + i * 60,
        "day": Checker.day_of(now),
        "status": "up",
        "ok": i != 1,
        "latency_ms": latency,
        "maintenance": false
      })
    end
    board = DashboardBoard.build(now)
    assert_eq(board["counts"]["up"], 1)
    assert_eq(board["counts"]["down"], 1)
    web = board["rows"].find do |row|
      row["name"] == "Web"
    end
    assert_contains(web["spark"], "<polyline")
    assert_contains(web["spark"], "class=\"fail\"")
    assert_eq(web["uptime_24h"], 66.667)
  end

  test("a paused or maintained monitor says so") do
    board_api.paused = true
    board_api.save
    now = DateTime.utc.to_unix
    Maintenance.create({
      "title": "M",
      "starts_at": now - 10,
      "ends_at": now + 60,
      "monitor_ids": [board_web._key]
    })
    rows = DashboardBoard.build(now)["rows"]
    assert_eq(rows.find(&{ |row|
      row["name"] == "API"
    })["status"], "paused")
    assert_eq(rows.find(&{ |row|
      row["name"] == "Web"
    })["status"], "maintenance")
    assert_eq(DashboardBoard.counts(rows)["other"], 2)
  end
end

describe("Sparkline and badge") do
  test("needs two points to draw") do
    assert_eq(Sparkline.svg([{"latency_ms": 10, "ok": true}], "x"), "")
  end

  test("cleans its label") do
    svg = Sparkline.svg([{"latency_ms": 10, "ok": true}, {
      "latency_ms": 20,
      "ok": true
    }], "A & <B>")
    assert_contains(svg, "aria-label=\"A et B\"")
  end

  test("a badge escapes its label and falls back to grey") do
    svg = BadgeSvg.render("R&D <lab>", "unknown", "en attente")
    assert_contains(svg, "R&amp;D &lt;lab&gt;")
    assert_contains(svg, "#6b7280")
    assert_eq(Xml.parse(svg).root.name, "svg")
  end
end

describe("Models") do
  before_each() do
    board_reset()
  end

  test("a monitor fills its defaults and labels") do
    monitor = Monitor.create({"name": "  Espaces  ", "url": "https://example.com"})
    assert_eq(monitor.name, "Espaces")
    assert_eq(monitor.interval_s, 60)
    assert_eq(monitor.failure_threshold, 2)
    assert_eq(monitor.kind_label, "HTTP(S)")
    assert_eq(monitor.target_label, "https://example.com")
    assert(monitor.due?(DateTime.utc.to_unix))
    tls = Monitor.create({
      "name": "Cert",
      "kind": "tls",
      "host": "Example.COM"
    })
    assert_eq(tls.target_label, "example.com:443")
    assert_eq(Monitor.label_for_kind("heartbeat"), "Heartbeat")
    assert(Monitor.active.length >= 2)
  end

  test("a monitor refuses unknown kinds, methods and status ranges") do
    bad = Monitor.create({"name": "X", "kind": "smtp"})
    assert_eq(bad._errors[0]["field"], "kind")
    weird = Monitor.create({
      "name": "X",
      "url": "https://example.com",
      "http_method": "TRACE",
      "status_min": 500,
      "status_max": 200,
      "timeout_s": 99,
      "failure_threshold": 0
    })
    fields = weird._errors.map do |error|
      error["field"]
    end
    assert_contains(fields, "http_method")
    assert_contains(fields, "status_max")
    assert_contains(fields, "timeout_s")
    assert_contains(fields, "failure_threshold")
    tls = Monitor.create({
      "name": "X",
      "kind": "tls",
      "host": "example.com",
      "port": 70000
    })
    assert_eq(tls._errors[0]["field"], "port")
  end

  test("incidents, updates and maintenances have French labels") do
    incident = Incident.create({
      "title": "T",
      "status": "monitoring",
      "monitor_ids": ["m"]
    })
    assert_eq(incident.status_label, "Sous surveillance")
    assert_eq(incident.impact_label, "Panne")
    assert_eq(Incident.label_for_status("identified"), "Identifié")
    update = IncidentUpdate.create({
      "incident_id": incident._key,
      "status": "identified",
      "message": "m",
      "at": 1
    })
    assert_eq(update.status_label, "Identifié")
    assert_eq(Incident.touching(["m"], 5).length, 1)
    refused = Incident.create({
      "title": "T",
      "status": "nope",
      "impact": "nope",
      "monitor_ids": ["m"]
    })
    assert_eq(refused._errors.length, 2)
    window = Maintenance.create({
      "title": "W",
      "starts_at": 100,
      "ends_at": 200,
      "monitor_ids": ["m"]
    })
    assert(window.upcoming_at?(50))
    assert(window.covers?("m"))
    assert_eq(window.active_at?(150), true)
  end

  test("a channel labels its kind; a page derives its slug") do
    channel = AlertChannel.create({
      "name": "S",
      "kind": "slack",
      "target": "https://hooks.slack.example.com/x"
    })
    assert_eq(channel.kind_label, "Slack")
    assert_eq(AlertChannel.new({"kind": "email"}).kind_label, "E-mail")
    assert_eq(AlertChannel.new({"kind": "webhook"}).kind_label, "Webhook JSON")
    page = StatusPage.create({"title": "Mon Service à moi"})
    assert_eq(page.slug, "mon-service-a-moi")
    component = Component.create({"name": "Sans page"})
    assert_eq(component._errors[0]["field"], "page_id")
  end
end

describe("DemoSeed") do
  test("builds a living demo, and running it twice changes nothing") do
    board_reset()
    first = DemoSeed.run(DateTime.utc.to_unix)
    assert_eq(first["page"], "demo")
    assert(first["monitors"] >= 4)
    page = StatusPage.find_by("slug", "demo")
    assert(page.components.length >= 3)
    assert(Incident.where({"kind": "auto"}).count >= 3)
    board = StatusBoard.build(page, DateTime.utc.to_unix)
    levels = board["components"][0]["bars"].map do |bar|
      bar["level"]
    end
    assert(levels.includes?("ok"))
    assert(levels.includes?("down") || levels.includes?("partial"))
    monitors_before = Monitor.count
    incidents_before = Incident.count
    second = DemoSeed.run(DateTime.utc.to_unix)
    assert_eq(Monitor.count, monitors_before)
    assert_eq(Incident.count, incidents_before)
    assert_eq(second["checks"], 0)
    assert_not_null(User.find_by("email", DEMO_EMAIL))
  end
end
