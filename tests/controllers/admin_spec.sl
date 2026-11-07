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

  test("lists a lone failure long after it left the latest checks") do
    monitor = Monitor.create({"name": "Docs", "url": "https://docs.example.com"})
    now = DateTime.utc.to_unix
    Check.create({
      "monitor_id": monitor._key,
      "at": now - 6 * 3600,
      "day": Checker.day_of(now - 6 * 3600),
      "status": "down",
      "ok": false,
      "http_status": 502,
      "error": "HTTP 502 (attendu 200–399)",
      "maintenance": false
    })
    (0 .. 40).each do |i|
      Check.create({
        "monitor_id": monitor._key,
        "at": now - i * 60,
        "day": Checker.day_of(now - i * 60),
        "status": "up",
        "ok": true,
        "latency_ms": 90,
        "maintenance": false
      })
    end
    get("/admin/sondes/#{monitor._key}")
    failures = assigns()["failures"]
    assert_eq(failures.length, 1)
    assert_eq(failures[0]["error"], "HTTP 502 (attendu 200–399)")
    assert_eq(assigns()["checks"].filter(&{ |check|
      check["status"] != "up"
    }).length, 0)
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
    assert_contains(res_body(get("/admin/sondes/#{monitor._key}")), "Aucun contrôle en échec")
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

  test("creates a page, then a service from a name and an address") do
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
    added = post(
      "/admin/pages/#{page._key}/composants",
      {
        "name": "API publique",
        "url": "https://api.example.com/sante",
        "group_name": "Plateforme",
        "position": "1"
      }
    )
    component = Component.find_by("slug", "api-publique")
    assert_eq(res_location(added), "/admin/composants/#{component._key}")
    assert_eq(component.position, 1)
    assert_eq(component.group_name, "Plateforme")
    http = Monitor.find_by("name", "API publique")
    certificate = Monitor.find_by("name", "Certificat api.example.com")
    assert_eq(http.url, "https://api.example.com/sante")
    assert_eq(http.interval_s, 60)
    assert_eq(certificate.kind, "tls")
    assert_eq(certificate.host, "api.example.com")
    assert_eq(component.monitor_ids, [http._key, certificate._key])
    body = res_body(get("/admin/pages/#{page._key}"))
    assert_contains(body, "API publique")
    assert_contains(body, "https://api.example.com/sante")
    assert_contains(body, "/badge/api-publique.svg")
    component_page = res_body(get("/admin/composants/#{component._key}"))
    assert_contains(component_page, "Sondes de ce service")
    assert_contains(component_page, "Certificat api.example.com")
    assert_contains(component_page, "Une tâche planifiée")
  end

  test("refuses a service without a name, without an address or with a bad one, and writes nothing") do
    page = StatusPage.create({"title": "Une", "slug": "une"})
    [
      {"name": "", "url": "https://api.example.com"},
      {"name": "API", "url": ""},
      {"name": "API", "url": "ftp://api.example.com"}
    ].each do |form|
      response = post("/admin/pages/#{page._key}/composants", form)
      assert_eq(res_location(response), "/admin/pages/#{page._key}")
      assert_eq(Component.count, 0)
      assert_eq(Monitor.count, 0)
    end
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "API", "url": "https://api.example.com"}
    )
    monitors_before = Monitor.count
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "API", "url": "https://autre.example.com"}
    )
    assert_eq(Component.count, 1, "a second service with the same name is refused")
    assert_eq(Monitor.count, monitors_before)
  end

  test("two services on one host share its certificate monitor; plain http has none") do
    page = StatusPage.create({"title": "Une", "slug": "une"})
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "Site", "url": "https://acme.example.com/"}
    )
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "Boutique", "url": "https://acme.example.com/shop"}
    )
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "Intranet", "url": "http://intranet.example.com/"}
    )
    assert_eq(Monitor.where({"kind": "tls"}).count, 1)
    certificate = Monitor.find_by("kind", "tls")
    assert_contains(Component.find_by("slug", "site").monitor_ids, certificate._key)
    assert_contains(Component.find_by("slug", "boutique").monitor_ids, certificate._key)
    assert_eq(Component.find_by("slug", "intranet").monitor_ids.length, 1)
    assert_eq(
      ServiceSetup.tls_endpoint("https://user@acme.example.com:8443/x?y"),
      {"host": "acme.example.com", "port": 8443}
    )
    assert_null(ServiceSetup.tls_endpoint("http://acme.example.com"))
  end

  test("renames a service and keeps its monitors") do
    page = StatusPage.create({"title": "Une", "slug": "une"})
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "API", "url": "https://api.example.com"}
    )
    component = Component.find_by("slug", "api")
    ids = component.monitor_ids
    patch(
      "/admin/composants/#{component._key}",
      {
        "name": "API v2",
        "group_name": "Plateforme",
        "position": "2"
      }
    )
    renamed = Component.find(component._key)
    assert_eq(renamed.slug, "api-v2")
    assert_eq(renamed.monitor_ids, ids, "saving the display keeps the monitors")
    page_body = res_body(get("/admin/composants/#{component._key}"))
    assert_contains(page_body, "Ajouter une sonde")
    assert_contains(page_body, "value=\"https://api.example.com/\"")
    assert_not(page_body.includes?("Rattacher"), "existing monitors are not offered")
  end

  test("adds a monitor of each kind to a service, with only the fields it needs") do
    page = StatusPage.create({"title": "Une", "slug": "une"})
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "API", "url": "https://api.example.com"}
    )
    component = Component.find_by("slug", "api")
    added = post(
      "/admin/composants/#{component._key}/sondes",
      {"kind": "http", "url": "https://api.example.com/sante"}
    )
    assert_eq(res_location(added), "/admin/composants/#{component._key}")
    health = Monitor.find_by("url", "https://api.example.com/sante")
    assert_eq(health.name, "API · https://api.example.com/sante")
    assert_eq(health.degraded_ms, 1500)
    post(
      "/admin/composants/#{component._key}/sondes",
      {
        "kind": "heartbeat",
        "every_hours": "6",
        "name": "Sauvegarde"
      }
    )
    backup = Monitor.find_by("name", "Sauvegarde")
    assert_eq(backup.kind, "heartbeat")
    assert_eq(backup.interval_s, 21600)
    assert_eq(backup.check_every, 60, "a heartbeat is evaluated every minute, whatever its period")
    assert_eq(health.check_every, 60)
    too_rare = post(
      "/admin/composants/#{component._key}/sondes",
      {"kind": "heartbeat", "every_hours": "200"}
    )
    assert_eq(res_status(too_rare), 422)
    post(
      "/admin/composants/#{component._key}/sondes",
      {
        "kind": "tls",
        "host": "API.example.com",
        "port": "443"
      }
    )
    assert_eq(Monitor.where({"kind": "tls"}).count, 1, "the certificate already watched is reused")
    post(
      "/admin/composants/#{component._key}/sondes",
      {
        "kind": "tls",
        "host": "mail.example.com",
        "port": "993"
      }
    )
    mail = Monitor.find_by("name", "Certificat mail.example.com")
    assert_eq(mail.port, 993)
    assert_eq(Component.find(component._key).monitor_ids.length, 5)
  end

  test("refuses a monitor with a bad address or an unknown kind, and writes nothing") do
    page = StatusPage.create({"title": "Une", "slug": "une"})
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "API", "url": "https://api.example.com"}
    )
    component = Component.find_by("slug", "api")
    monitors_before = Monitor.count
    bad = post(
      "/admin/composants/#{component._key}/sondes",
      {"kind": "http", "url": "ftp://api.example.com"}
    )
    assert_eq(res_status(bad), 422)
    assert_contains(res_body(bad), "Sonde refusée")
    assert_eq(res_status(post("/admin/composants/#{component._key}/sondes", {"kind": "udp"})), 422)
    assert_eq(res_status(post(
      "/admin/composants/#{component._key}/sondes",
      {"kind": "tls", "host": ""}
    )), 422)
    assert_eq(Monitor.count, monitors_before)
    assert_eq(Component.find(component._key).monitor_ids.length, 2)
    assert_eq(res_status(post("/admin/composants/nope/sondes", {"kind": "http"})), 404)
  end

  test("removing a monitor from a service deletes it, unless another service uses it") do
    page = StatusPage.create({"title": "Une", "slug": "une"})
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "Site", "url": "https://acme.example.com/"}
    )
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "Boutique", "url": "https://acme.example.com/shop"}
    )
    site = Component.find_by("slug", "site")
    http = Monitor.find_by("name", "Site")
    certificate = Monitor.find_by("kind", "tls")
    delete("/admin/composants/#{site._key}/sondes/#{certificate._key}")
    assert_eq(Component.find(site._key).monitor_ids, [http._key])
    assert_not_null(Monitor.find_by("kind", "tls"), "Boutique still uses the certificate")
    delete("/admin/composants/#{site._key}/sondes/#{http._key}")
    assert_null(Monitor.find_by("name", "Site"))
    assert_eq(Component.find(site._key).monitor_ids, [])
  end

  test("removing a service takes the monitors only it used, and keeps shared ones") do
    page = StatusPage.create({"title": "Une", "slug": "une"})
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "Site", "url": "https://acme.example.com/"}
    )
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "Boutique", "url": "https://acme.example.com/shop"}
    )
    site = Component.find_by("slug", "site")
    http = Monitor.find_by("name", "Site")
    Check.create({
      "monitor_id": http._key,
      "at": DateTime.utc.to_unix,
      "status": "up",
      "ok": true
    })
    DailyRollup.create({
      "monitor_id": http._key,
      "day": Checker.day_of(DateTime.utc.to_unix),
      "total": 1,
      "up": 1
    })
    delete("/admin/composants/#{site._key}")
    assert_null(Component.find_by("slug", "site"))
    assert_null(Monitor.find_by("name", "Site"))
    assert_eq(Check.where({"monitor_id": http._key}).count, 0)
    assert_eq(DailyRollup.where({"monitor_id": http._key}).count, 0)
    assert_not_null(Monitor.find_by("kind", "tls"), "the certificate is still used by Boutique")
    assert_eq(Component.find_by("slug", "boutique").monitor_ids.length, 2)
  end

  test("deleting a monitor takes it off its services") do
    page = StatusPage.create({"title": "Une", "slug": "une"})
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "API", "url": "https://api.example.com"}
    )
    certificate = Monitor.find_by("kind", "tls")
    delete("/admin/sondes/#{certificate._key}")
    assert_eq(Component.find_by("slug", "api").monitor_ids, [Monitor.find_by("name", "API")._key])
  end

  test("lists monitors page by page and service by service, then those on no page") do
    page = StatusPage.create({"title": "Acme", "slug": "acme"})
    post(
      "/admin/pages/#{page._key}/composants",
      {"name": "API", "url": "https://api.example.com"}
    )
    Monitor.create({"name": "Orpheline", "url": "https://orphan.example.com"})
    get("/admin/sondes")
    sections = assigns()["sections"]
    assert_eq(sections.map(&{ |section|
      section["title"]
    }), ["Acme", "Sur aucune page"])
    assert_eq(sections[0]["rows"].length, 2)
    assert_eq(sections[0]["rows"][0]["first"], true)
    assert_eq(sections[0]["rows"][1]["first"], false)
    assert_eq(sections[1]["rows"][0]["monitor"]["name"], "Orpheline")
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
    incident_form = get("/admin/incidents/nouveau")
    assert_eq(res_status(incident_form), 200)
    assert_contains(res_body(incident_form), "affiche sur les services de la page publique")
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
    maintenance_form = get("/admin/maintenances/nouvelle")
    assert_eq(res_status(maintenance_form), 200)
    assert_contains(res_body(maintenance_form), "Services concernés")
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
    page = StatusPage.create({"title": "Acme", "slug": "acme"})
    service = Component.create({
      "page_id": page._key,
      "name": "Site",
      "monitor_ids": [monitor._key]
    })
    second = Monitor.create({
      "name": "Certificat",
      "kind": "tls",
      "host": "api.example.com"
    })
    service.monitor_ids = [monitor._key, second._key]
    service.save
    patch(
      "/admin/maintenances/#{window._key}",
      {
        "title": "Bascule 2",
        "starts_at_local": "2030-01-02T03:00",
        "ends_at_local": "2030-01-02T05:00",
        "monitor_ids": ["#{monitor._key},#{second._key}", monitor._key]
      }
    )
    assert_eq(
      Maintenance.find(window._key).monitor_ids,
      [monitor._key, second._key],
      "a service box stands for its monitors"
    )
    ticked = res_body(get("/admin/maintenances/#{window._key}"))
    assert_contains(ticked, "value=\"#{monitor._key},#{second._key}\" checked")
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
