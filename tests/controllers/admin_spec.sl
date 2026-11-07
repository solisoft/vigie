admin_user = nil

def admin_reset
  models = [
    Check,
    DailyRollup,
    Incident,
    IncidentUpdate,
    Maintenance,
    Component,
    StatusPage,
    Monitor,
    AlertChannel,
    AlertDelivery
  ]
  models.each do |model|
    model.all.each do |record|
      record.delete
    end
  end
  admin_user = User.find_by("email", "admin@vigie.example")
  return admin_user unless admin_user.nil?

  admin_user = User.new()
  admin_user.email = "admin@vigie.example"
  admin_user.set_password("correct horse battery staple")
  admin_user.save
  admin_user
end

# A real POST /login, once per describe: the sign-in throttle allows 15
# attempts per address in 5 minutes. (with_session / as_user do not reach the
# server's in-memory session, and as_user wants an Int id; SoliDB keys are
# strings.)
def admin_sign_in
  admin_reset()
  login("admin@vigie.example", "correct horse battery staple")
end

describe("Admin access") do
  before_each() do
    admin_reset()
    as_guest()
  end

  test("a guest is sent to the sign-in page, on every admin screen") do
    [
      "/admin",
      "/admin/sondes",
      "/admin/sondes/nouvelle",
      "/admin/pages",
      "/admin/incidents",
      "/admin/maintenances",
      "/admin/alertes"
    ].each do |path|
      response = get(path)
      assert_eq(res_status(response), 302, path)
      assert_eq(res_location(response), "/login", path)
    end
  end

  test("a guest cannot create a monitor, and nothing is written") do
    response = post(
      "/admin/sondes",
      {
        "name": "Intrus",
        "kind": "http",
        "url": "https://example.com"
      }
    )
    assert_eq(res_status(response), 302)
    assert_eq(Monitor.count, 0)
  end

  test("the sign-in page is in French, and a wrong password is refused") do
    assert_contains(res_body(get("/login")), "Se connecter")
    response = post(
      "/login",
      {"email": "admin@vigie.example", "password": "wrong password here"}
    )
    assert_eq(res_status(response), 401)
    assert_contains(res_body(response), "E-mail ou mot de passe incorrect")
  end

  test("the right password leads to the dashboard") do
    response = post(
      "/login",
      {"email": "admin@vigie.example", "password": "correct horse battery staple"}
    )
    assert_eq(res_status(response), 302)
    assert_eq(res_location(response), "/admin")
  end

  test("sign-up is closed once an account exists") do
    assert_eq(res_location(get("/signup")), "/login")
    response = post(
      "/signup",
      {"email": "second@vigie.example", "password": "another long passphrase"}
    )
    assert_eq(res_location(response), "/login")
    assert_eq(User.count, 1)
  end

  test("sign-up opens for the very first account") do
    admin_user.delete
    assert_eq(res_status(get("/signup")), 200)
    response = post(
      "/signup",
      {"email": "first@vigie.example", "password": "the first passphrase"}
    )
    assert_eq(res_location(response), "/admin")
    assert_eq(User.count, 1)
    User.find_by("email", "first@vigie.example").delete
    as_guest()
  end
end

describe("Admin dashboard and monitors") do
  before_all() do
    admin_sign_in()
  end

  before_each() do
    admin_reset()
  end

  test("the dashboard lists monitors with their state") do
    monitor = Monitor.create({"name": "Boutique", "url": "https://shop.example.com"})
    Check.create({
      "monitor_id": monitor._key,
      "at": DateTime.utc.to_unix - 60,
      "day": Checker.day_of(DateTime.utc.to_unix - 60),
      "status": "up",
      "ok": true,
      "latency_ms": 120,
      "maintenance": false
    })
    Check.create({
      "monitor_id": monitor._key,
      "at": DateTime.utc.to_unix - 30,
      "day": Checker.day_of(DateTime.utc.to_unix - 30),
      "status": "down",
      "ok": false,
      "latency_ms": 900,
      "maintenance": false
    })
    response = get("/admin")
    assert_eq(res_status(response), 200)
    body = res_body(response)
    assert_contains(body, "Boutique")
    assert_contains(body, "class=\"spark\"")
    assert_contains(body, "<a class=\"rail-brand\" href=\"/\">")
    assert_contains(body, "class=\"fail\"")
    assert_contains(body, "data-live-url=\"/admin/live\"")
  end

  test("creates an HTTP monitor from the form") do
    response = post(
      "/admin/sondes",
      {
        "name": "Boutique",
        "kind": "http",
        "url": "https://shop.example.com",
        "interval_s": "120",
        "failure_threshold": "3",
        "timeout_s": "5",
        "status_min": "200",
        "status_max": "299",
        "follow_redirects": "true",
        "keyword": "Panier"
      }
    )
    assert_eq(res_status(response), 302)
    monitor = Monitor.find_by("name", "Boutique")
    assert_eq(monitor.interval_s, 120)
    assert_eq(monitor.failure_threshold, 3)
    assert_eq(monitor.status_max, 299)
    assert_eq(monitor.follow_redirects, true)
    assert_eq(monitor.status, "pending")
    assert_eq(res_location(response), "/admin/sondes/#{monitor._key}")
  end

  test("refuses a private target, a bad interval and a blank name, and writes nothing") do
    # (.env.test lifts the private-address refusal for the mock server; the
    # refusal itself is proven in target_guard_spec.)
    response = post(
      "/admin/sondes",
      {
        "name": "",
        "kind": "http",
        "url": "gopher://169.254.169.254/latest",
        "interval_s": "5"
      }
    )
    assert_eq(res_status(response), 422)
    body = res_body(response)
    assert_contains(body, "doit commencer par http:// ou https://")
    assert_contains(body, "entre 30 s et 1 h")
    assert_contains(body, "est obligatoire")
    assert_eq(Monitor.count, 0)
  end

  test("refuses a TLS monitor without a host") do
    response = post(
      "/admin/sondes",
      {
        "name": "Certificat",
        "kind": "tls",
        "host": "",
        "port": "443",
        "interval_s": "3600"
      }
    )
    assert_eq(res_status(response), 422)
    assert_eq(Monitor.count, 0)
  end

  test("creates a heartbeat with a secret token, shown on its page") do
    post(
      "/admin/sondes",
      {
        "name": "Sauvegarde",
        "kind": "heartbeat",
        "interval_s": "3600",
        "grace_s": "300"
      }
    )
    monitor = Monitor.find_by("name", "Sauvegarde")
    assert_eq(monitor.heartbeat_token.length, 32)
    body = res_body(get("/admin/sondes/#{monitor._key}"))
    assert_contains(body, "/ping/#{monitor.heartbeat_token}")
  end

  test("shows, edits and deletes a monitor") do
    monitor = Monitor.create({"name": "Blog", "url": "https://blog.example.com"})
    Check.create({
      "monitor_id": monitor._key,
      "at": DateTime.utc.to_unix,
      "day": Checker.day_of(DateTime.utc.to_unix),
      "status": "up",
      "ok": true,
      "latency_ms": 80,
      "maintenance": false
    })
    assert_contains(res_body(get("/admin/sondes")), "Blog")
    assert_contains(res_body(get("/admin/sondes/#{monitor._key}")), "Derniers contrôles")
    assert_eq(res_status(get("/admin/sondes/#{monitor._key}/modifier")), 200)
    response = patch(
      "/admin/sondes/#{monitor._key}",
      {
        "name": "Blog v2",
        "kind": "http",
        "url": "https://blog.example.com",
        "interval_s": "300",
        "paused": "true"
      }
    )
    assert_eq(res_status(response), 302)
    updated = Monitor.find(monitor._key)
    assert_eq(updated.name, "Blog v2")
    assert_eq(updated.interval_s, 300)
    assert_eq(updated.paused, true)
    bad = patch(
      "/admin/sondes/#{monitor._key}",
      {
        "name": "Blog v2",
        "kind": "http",
        "url": "ftp://blog",
        "interval_s": "300"
      }
    )
    assert_eq(res_status(bad), 422)
    assert_eq(Monitor.find(monitor._key).url, "https://blog.example.com")
    delete("/admin/sondes/#{monitor._key}")
    assert_eq(Monitor.count, 0)
    assert_eq(Check.count, 0)
  end

  test("check now enqueues a probe") do
    monitor = Monitor.create({"name": "Blog", "url": "https://blog.example.com"})
    response = post("/admin/sondes/#{monitor._key}/verifier", {})
    assert_eq(res_status(response), 302)
    assert_eq(res_status(get("/admin/sondes/nope")), 404)
  end
end

describe("Admin pages and components") do
  before_all() do
    admin_sign_in()
  end

  before_each() do
    admin_reset()
  end

  test("creates a page, adds a component, renames it, removes it") do
    monitor = Monitor.create({"name": "API", "url": "https://api.example.com"})
    assert_eq(res_status(get("/admin/pages/nouvelle")), 200)
    response = post(
      "/admin/pages",
      {
        "title": "Statut Acme",
        "slug": "",
        "published": "true"
      }
    )
    page = StatusPage.find_by("slug", "statut-acme")
    assert_eq(res_location(response), "/admin/pages/#{page._key}")
    assert_eq(page.published, true)
    assert_eq(page.listed, false, "an unchecked box hides the page from the landing page")
    patch(
      "/admin/pages/#{page._key}",
      {
        "title": "Statut Acme",
        "slug": "statut-acme",
        "published": "true",
        "listed": "true"
      }
    )
    assert_eq(StatusPage.find(page._key).listed, true)
    post(
      "/admin/pages/#{page._key}/composants",
      {
        "name": "API publique",
        "group_name": "Plateforme",
        "position": "1",
        "monitor_ids": [monitor._key]
      }
    )
    component = Component.find_by("slug", "api-publique")
    assert_eq(component.monitor_ids, [monitor._key])
    assert_eq(component.position, 1)
    body = res_body(get("/admin/pages/#{page._key}"))
    assert_contains(body, "API publique")
    assert_contains(body, "/badge/api-publique.svg")
    assert_eq(res_status(get("/admin/composants/#{component._key}")), 200)
    patch(
      "/admin/composants/#{component._key}",
      {
        "name": "API v2",
        "group_name": "Plateforme",
        "position": "2",
        "monitor_ids": [monitor._key]
      }
    )
    assert_eq(Component.find(component._key).name, "API v2")
    assert_eq(Component.find(component._key).slug, "api-v2")
    delete("/admin/composants/#{component._key}")
    assert_eq(Component.count, 0)
    assert_contains(res_body(get("/admin/pages")), "Statut Acme")
  end

  test("refuses a duplicate slug on create and on update, and a bad logo URL") do
    StatusPage.create({"title": "Une", "slug": "une"})
    other = StatusPage.create({"title": "Deux", "slug": "deux"})
    response = post(
      "/admin/pages",
      {
        "title": "Encore",
        "slug": "une",
        "logo_url": "javascript:alert(1)"
      }
    )
    assert_eq(res_status(response), 422)
    assert_contains(res_body(response), "déjà utilisé")
    assert_contains(res_body(response), "https://")
    assert_eq(StatusPage.count, 2)
    clash = patch(
      "/admin/pages/#{other._key}",
      {"title": "Deux", "slug": "une"}
    )
    assert_eq(res_status(clash), 422)
    assert_eq(StatusPage.find(other._key).slug, "deux")
    kept = patch(
      "/admin/pages/#{other._key}",
      {"title": "Deux bis", "slug": "deux"}
    )
    assert_eq(res_status(kept), 302)
    assert_eq(StatusPage.find(other._key).title, "Deux bis")
  end

  test("refuses a component whose name is taken, and a page deletion takes its components") do
    page = StatusPage.create({"title": "Une", "slug": "une"})
    Component.create({"page_id": page._key, "name": "API"})
    post("/admin/pages/#{page._key}/composants", {"name": "API"})
    assert_eq(Component.count, 1)
    other = Component.create({"page_id": page._key, "name": "Web"})
    clash = patch("/admin/composants/#{other._key}", {"name": "API"})
    assert_eq(res_status(clash), 422)
    delete("/admin/pages/#{page._key}")
    assert_eq(StatusPage.count, 0)
    assert_eq(Component.count, 0)
  end
end

describe("Admin incidents") do
  before_all() do
    admin_sign_in()
  end

  before_each() do
    admin_reset()
    Mailer.clear_deliveries()
  end

  test("declares a manual incident, which the public page shows, then resolves it with one alert each way") do
    monitor = Monitor.create({"name": "API", "url": "https://api.example.com"})
    page = StatusPage.create({"title": "Acme", "slug": "acme"})
    Component.create({
      "page_id": page._key,
      "name": "API",
      "monitor_ids": [monitor._key]
    })
    AlertChannel.create({
      "name": "Ops",
      "kind": "webhook",
      "target": "https://hooks.example.com/x"
    })
    assert_eq(res_status(get("/admin/incidents/nouveau")), 200)
    response = post(
      "/admin/incidents",
      {
        "title": "Lenteurs API",
        "status": "identified",
        "impact": "degraded",
        "message": "Un index manque.",
        "monitor_ids": [monitor._key]
      }
    )
    incident = Incident.find_by("title", "Lenteurs API")
    assert_eq(res_location(response), "/admin/incidents/#{incident._key}")
    assert_eq(incident.kind, "manual")
    assert_eq(incident.updates[0].message, "Un index manque.")
    assert_contains(res_body(get("/s/acme")), "Lenteurs API")
    assert_contains(res_body(get("/s/acme")), "Performances dégradées")
    assert_contains(res_body(get("/admin/incidents/#{incident._key}")), "Publier un suivi")
    post(
      "/admin/incidents/#{incident._key}/suivis",
      {"status": "resolved", "message": "Index ajouté."}
    )
    resolved = Incident.find(incident._key)
    assert_eq(resolved.status, "resolved")
    assert_eq(resolved.updates.length, 2)
    assert_eq(AlertDelivery.where({"event": "incident.opened"}).count, 1)
    assert_eq(AlertDelivery.where({"event": "incident.resolved"}).count, 1)
    assert_contains(res_body(get("/admin/incidents")), "Lenteurs API")
  end

  test("refuses an incident without a title or a monitor, and an update without a message") do
    response = post(
      "/admin/incidents",
      {
        "title": "",
        "status": "investigating",
        "impact": "outage"
      }
    )
    assert_eq(res_status(response), 422)
    assert_contains(res_body(response), "choisissez au moins une sonde")
    assert_eq(Incident.count, 0)
    monitor = Monitor.create({"name": "API", "url": "https://api.example.com"})
    incident = Incident.create({
      "title": "X",
      "monitor_ids": [monitor._key]
    })
    post(
      "/admin/incidents/#{incident._key}/suivis",
      {"status": "resolved", "message": ""}
    )
    assert_eq(Incident.find(incident._key).status, "investigating")
    post(
      "/admin/incidents/#{incident._key}/suivis",
      {"status": "bogus", "message": "x"}
    )
    assert_eq(Incident.find(incident._key).status, "investigating")
    delete("/admin/incidents/#{incident._key}")
    assert_eq(Incident.count, 0)
  end
end

describe("Admin maintenances") do
  before_all() do
    admin_sign_in()
  end

  before_each() do
    admin_reset()
  end

  test("plans, edits and deletes a window in UTC") do
    monitor = Monitor.create({"name": "API", "url": "https://api.example.com"})
    assert_eq(res_status(get("/admin/maintenances/nouvelle")), 200)
    post(
      "/admin/maintenances",
      {
        "title": "Bascule",
        "starts_at_local": "2030-01-02T03:00",
        "ends_at_local": "2030-01-02T04:30",
        "monitor_ids": [monitor._key]
      }
    )
    window = Maintenance.find_by("title", "Bascule")
    assert_eq(window.starts_at, DateTime.parse("2030-01-02T03:00:00Z").to_unix)
    assert_eq(window.ends_at - window.starts_at, 5400)
    assert_eq(window.monitor_ids, [monitor._key])
    assert_contains(res_body(get("/admin/maintenances")), "Bascule")
    edit_body = res_body(get("/admin/maintenances/#{window._key}"))
    assert_contains(edit_body, "2030-01-02T03:00")
    patch(
      "/admin/maintenances/#{window._key}",
      {
        "title": "Bascule 2",
        "starts_at_local": "2030-01-02T03:00",
        "ends_at_local": "2030-01-02T05:00",
        "monitor_ids": [monitor._key]
      }
    )
    assert_eq(Maintenance.find(window._key).title, "Bascule 2")
    bad = patch(
      "/admin/maintenances/#{window._key}",
      {
        "title": "Bascule 2",
        "starts_at_local": "2030-01-02T05:00",
        "ends_at_local": "2030-01-02T04:00"
      }
    )
    assert_eq(res_status(bad), 422)
    delete("/admin/maintenances/#{window._key}")
    assert_eq(Maintenance.count, 0)
  end

  test("refuses a window that ends before it starts, and writes nothing") do
    response = post(
      "/admin/maintenances",
      {
        "title": "À l'envers",
        "starts_at_local": "2030-01-02T05:00",
        "ends_at_local": "2030-01-02T04:00"
      }
    )
    assert_eq(res_status(response), 422)
    assert_contains(res_body(response), "doit suivre le début")
    assert_eq(Maintenance.count, 0)
  end
end

describe("Admin alert channels") do
  before_all() do
    admin_sign_in()
  end

  before_each() do
    admin_reset()
    Mailer.clear_deliveries()
  end

  test("adds an e-mail channel, tests it, deletes it") do
    assert_eq(res_status(get("/admin/alertes")), 200)
    post(
      "/admin/alertes",
      {
        "name": "Astreinte",
        "kind": "email",
        "target": "ops@acme.example",
        "active": "true"
      }
    )
    channel = AlertChannel.find_by("name", "Astreinte")
    assert_eq(channel.active, true)
    response = post("/admin/alertes/#{channel._key}/test", {})
    assert_eq(res_status(response), 302)
    delete("/admin/alertes/#{channel._key}")
    assert_eq(AlertChannel.count, 0)
  end

  test("refuses a bad address and a non-http webhook URL") do
    response = post(
      "/admin/alertes",
      {
        "name": "Mail",
        "kind": "email",
        "target": "pas-une-adresse"
      }
    )
    assert_eq(res_status(response), 422)
    assert_contains(res_body(response), "adresse e-mail invalide")
    private_hook = post(
      "/admin/alertes",
      {
        "name": "Hook",
        "kind": "webhook",
        "target": "ftp://hooks.example.com/hook"
      }
    )
    assert_eq(res_status(private_hook), 422)
    assert_eq(AlertChannel.count, 0)
  end
end
