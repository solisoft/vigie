public_page = nil
public_monitor = nil

def public_reset
  [Check, DailyRollup, Incident, IncidentUpdate, Maintenance, Component, StatusPage, Monitor].each do |model|
    model.all.each do |record|
      record.delete
    end
  end
  public_monitor = Monitor.create({
    "name": "API publique",
    "url": "https://api.example.com/health",
    "interval_s": 60
  })
  public_page = StatusPage.create({
    "title": "Acme",
    "slug": "acme",
    "description": "État des services Acme",
    "published": true
  })
  Component.create({
    "page_id": public_page._key,
    "name": "API Acme",
    "group_name": "Plateforme",
    "monitor_ids": [public_monitor._key]
  })
end

def public_mark(status)
  public_monitor.status = status
  public_monitor.save
end

describe("GET /s/:slug") do
  before_each() do
    public_reset()
  end

  test("shows the banner, the components and the 90-day strip, cacheable") do
    public_mark("up")
    response = get("/s/acme")
    assert_eq(res_status(response), 200)
    body = res_body(response)
    assert_contains(body, "Tous les systèmes sont opérationnels")
    assert_contains(body, "API Acme")
    assert_contains(body, "Plateforme")
    assert_contains(body, "data-live-url=\"/s/acme/live\"")
    assert_contains(body, "/s/acme/incidents.atom")
    assert_eq(body.scan("class=\"b-").length, 90)
    assert_eq(res_header(response, "Cache-Control"), "public, max-age=15")
  end

  test("says outage in words, not only in colour") do
    public_mark("down")
    body = res_body(get("/s/acme"))
    assert_contains(body, "Panne générale")
    assert_contains(body, "chip s-down")
    assert_contains(body, ">Panne<")
  end

  test("shows an open incident with its timeline") do
    public_mark("down")
    incident = Incident.create({
      "title": "API Acme ne répond plus",
      "kind": "auto",
      "monitor_ids": [public_monitor._key],
      "started_at": DateTime.utc.to_unix - 120
    })
    IncidentUpdate.create({
      "incident_id": incident._key,
      "status": "investigating",
      "message": "Vigie a constaté 2 échecs",
      "at": DateTime.utc.to_unix - 120
    })
    body = res_body(get("/s/acme"))
    assert_contains(body, "Incidents en cours")
    assert_contains(body, "API Acme ne répond plus")
    assert_contains(body, "Vigie a constaté 2 échecs")
  end

  test("shows a maintenance in progress, and the monitor as in maintenance") do
    public_mark("down")
    now = DateTime.utc.to_unix
    Maintenance.create({
      "title": "Mise à jour de la base",
      "starts_at": now - 60,
      "ends_at": now + 3600,
      "monitor_ids": [public_monitor._key]
    })
    body = res_body(get("/s/acme"))
    assert_contains(body, "Maintenance en cours")
    assert_contains(body, "Mise à jour de la base")
  end

  test("answers 404 for an unknown or unpublished page") do
    assert_eq(res_status(get("/s/nope")), 404)
    public_page.published = false
    public_page.save
    assert_eq(res_status(get("/s/acme")), 404)
  end

  test("shows one incident on its own page") do
    incident = Incident.create({
      "title": "Lenteurs",
      "kind": "manual",
      "impact": "degraded",
      "status": "resolved",
      "monitor_ids": [public_monitor._key],
      "started_at": 1800000000,
      "resolved_at": 1800000600
    })
    response = get("/s/acme/incidents/#{incident._key}")
    assert_eq(res_status(response), 200)
    assert_contains(res_body(response), "Lenteurs")
    assert_contains(res_body(response), "10 min")
    assert_eq(res_status(get("/s/acme/incidents/nope")), 404)
  end
end

describe("GET / (home)") do
  test("is a landing page listing published pages with their state") do
    public_reset()
    public_mark("up")
    response = get("/")
    assert_eq(res_status(response), 200)
    body = res_body(response)
    assert_contains(body, "Ce que fait Vigie")
    assert_contains(body, "id=\"installer\"")
    assert_contains(body, "git clone https://github.com/solisoft/vigie.git")
    assert_contains(body, "href=\"/s/acme\"")
    assert_contains(body, "Acme")
    assert_contains(body, "1 service sous surveillance")
    assert_contains(body, "chip s-ok")
    assert_contains(body, "Tous les systèmes sont opérationnels")
    assert_contains(body, "og:title")
    assert_contains(body, "href=\"https://github.com/solisoft/vigie\"")
    assert_eq(assigns()["pages"].length, 1)
    assert_eq(StatusPage.find(public_page._key).listed, true)
  end

  test("leaves a page hidden from the landing page off it, still public") do
    public_reset()
    public_page.listed = false
    public_page.save
    body = res_body(get("/"))
    assert_not(body.includes?("/s/acme"))
    assert_eq(assigns()["pages"].length, 0)
    assert_eq(res_status(get("/s/acme")), 200)
  end

  test("says an outage on the landing page, in words") do
    public_reset()
    public_mark("down")
    body = res_body(get("/"))
    assert_contains(body, "chip s-major")
    assert_contains(body, "Panne générale")
  end

  test("leaves unpublished pages off the landing page") do
    public_reset()
    public_page.published = false
    public_page.save
    response = get("/")
    assert_eq(res_status(response), 200)
    body = res_body(response)
    assert_contains(body, "Aucune page de statut")
    assert_not(body.includes?("/s/acme"))
    assert_eq(assigns()["services"], 0)
  end

  test("health answers ok") do
    assert_eq(res_json(get("/health"))["status"], "ok")
  end
end

describe("GET /s/:slug/incidents.atom") do
  before_each() do
    public_reset()
  end

  test("is a well-formed Atom feed with escaped incidents") do
    incident = Incident.create({
      "title": "Panne <base> & cache",
      "kind": "manual",
      "status": "resolved",
      "monitor_ids": [public_monitor._key],
      "started_at": 1800000000,
      "resolved_at": 1800000600
    })
    IncidentUpdate.create({
      "incident_id": incident._key,
      "status": "resolved",
      "message": "Tout est rentré dans l'ordre",
      "at": 1800000600
    })
    response = get("/s/acme/incidents.atom")
    assert_eq(res_status(response), 200)
    assert_contains(res_header(response, "Content-Type"), "application/atom+xml")
    feed = Xml.parse(res_body(response))
    assert_eq(feed.root.name, "feed")
    assert_eq(feed.find("title").text, "Acme — incidents")
    assert_eq(feed.find_all("entry").length, 1)
    assert_eq(feed.find("entry/title").text, "[Résolu] Panne <base> & cache")
    assert_eq(feed.find("entry/updated").text, "2027-01-15T08:10:00Z")
    assert_contains(feed.find("entry/content").text, "Tout est rentré dans l'ordre")
  end

  test("is valid with no incident at all") do
    feed = Xml.parse(res_body(get("/s/acme/incidents.atom")))
    assert_eq(feed.find_all("entry").length, 0)
  end
end

describe("GET /api/v1/status") do
  before_each() do
    public_reset()
  end

  test("lists published pages, their status and component uptime") do
    public_mark("degraded")
    response = get("/api/v1/status")
    assert_eq(res_status(response), 200)
    assert_eq(res_header(response, "Access-Control-Allow-Origin"), "*")
    data = res_json(response)
    page = data["pages"][0]
    assert_eq(page["slug"], "acme")
    assert_eq(page["status"]["level"], "degraded")
    assert_eq(page["components"][0]["name"], "API Acme")
    assert_eq(page["components"][0]["status"], "degraded")
    assert(page["components"][0]["uptime"].has_key("90d"))
    assert(!page["components"][0].has_key("bars"))
  end

  test("filters by page, and answers 404 for an unknown one") do
    assert_eq(res_json(get("/api/v1/status?page=acme"))["pages"].length, 1)
    assert_eq(res_status(get("/api/v1/status?page=nope")), 404)
  end
end

describe("GET /badge/:slug.svg") do
  before_each() do
    public_reset()
  end

  test("draws the component's status in words") do
    public_mark("up")
    response = get("/badge/api-acme.svg")
    assert_eq(res_status(response), 200)
    assert_contains(res_header(response, "Content-Type"), "image/svg+xml")
    svg = Xml.parse(res_body(response))
    assert_eq(svg.root["aria-label"], "API Acme : opérationnel")
    assert_contains(res_body(response), "#1f7a4d")
  end

  test("turns red and says panne when down") do
    public_mark("down")
    body = res_body(get("/badge/api-acme.svg"))
    assert_contains(body, "panne")
    assert_contains(body, "#b42318")
  end

  test("404 for an unknown component, a non-svg name or an unpublished page") do
    assert_eq(res_status(get("/badge/nope.svg")), 404)
    assert_eq(res_status(get("/badge/api-acme.png")), 404)
    public_page.published = false
    public_page.save
    assert_eq(res_status(get("/badge/api-acme.svg")), 404)
  end
end

describe("Heartbeat /ping/:token") do
  before_each() do
    public_reset()
  end

  test("records the ping and recovers a down heartbeat at once") do
    beat = Monitor.create({
      "name": "Cron nocturne",
      "kind": "heartbeat",
      "interval_s": 3600
    })
    beat.status = "down"
    beat.consecutive_failures = 3
    beat.save
    response = post("/ping/#{beat.heartbeat_token}", {})
    assert_eq(res_status(response), 200)
    assert_eq(res_body(response), "OK")
    stored = Monitor.find(beat._key)
    assert(stored.last_heartbeat_at > 0)
    assert_eq(stored.status, "up")
    assert_eq(Check.where({"monitor_id": beat._key}).count, 1)
  end

  test("a GET works too, and an already-up heartbeat adds no check") do
    beat = Monitor.create({
      "name": "Cron horaire",
      "kind": "heartbeat",
      "interval_s": 3600
    })
    beat.status = "up"
    beat.save
    assert_eq(res_status(get("/ping/#{beat.heartbeat_token}")), 200)
    assert_eq(Check.where({"monitor_id": beat._key}).count, 0)
  end

  test("404 for an unknown token, or the token of a non-heartbeat monitor") do
    assert_eq(res_status(get("/ping/unknown-token")), 404)
    assert_eq(res_status(get("/ping/")), 404)
  end
end
