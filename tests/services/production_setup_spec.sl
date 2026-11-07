def production_reset
  [Check, DailyRollup, Component, StatusPage, Monitor, User].each do |model|
    model.all.each do |record|
      record.delete
    end
  end
end

describe("ProductionSetup") do
  before_each() do
    production_reset()
  end

  test("creates the page, one component and two monitors per site") do
    summary = ProductionSetup.run
    page = StatusPage.find_by("slug", "solisoft")
    assert_eq(page.listed, false, "the production page stays off the landing page")
    assert_eq(summary["page"], "solisoft")
    assert_eq(summary["monitors"], PRODUCTION_SITES.length * 2)
    assert_eq(Monitor.count, PRODUCTION_SITES.length * 2)
    assert_eq(Component.where({"page_id": page._key}).count, PRODUCTION_SITES.length)
    assert_null(summary["user"])
  end

  test("a site's path and redirect setting reach its HTTP monitor") do
    ProductionSetup.run
    docs = ProductionSetup.site_monitors([
      "Docs",
      "docs.example.com",
      "Clients",
      "La doc",
      399,
      "/fr"
    ])[0]
    assert_eq(docs.url, "https://docs.example.com/fr")
    assert_eq(docs.follow_redirects, false)
    assert_null(Monitor.find_by("name", "Villa Vladimir"))
    assert_eq(Monitor.find_by("name", "Vitaliseur").follow_redirects, true)
    assert_eq(Monitor.find_by("name", "CSW admin").status_max, 401)
    assert_eq(Monitor.find_by("name", "Certificat grc.solisoft.net").kind, "tls")
  end

  test("a second run adds nothing and puts a changed monitor back in step") do
    ProductionSetup.run
    vitaliseur = Monitor.find_by("name", "Vitaliseur")
    vitaliseur.url = "https://vitaliseur.com/ailleurs"
    vitaliseur.save
    ProductionSetup.run
    assert_eq(Monitor.count, PRODUCTION_SITES.length * 2)
    assert_eq(Component.count, PRODUCTION_SITES.length)
    assert_eq(Monitor.find_by("name", "Vitaliseur").url, "https://vitaliseur.com/")
  end

  test("creates the admin account once, and nothing without a password") do
    first = ProductionSetup.admin("ops@example.com", "a-long-production-password")
    second = ProductionSetup.admin("ops@example.com", "a-long-production-password")
    assert_eq(first.email, "ops@example.com")
    assert_eq(first.role, "admin")
    assert_eq(second._key, first._key)
    assert_eq(User.count, 1)
    assert_null(ProductionSetup.admin("ops@example.com", ""))
  end
end
