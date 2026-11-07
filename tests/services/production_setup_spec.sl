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
    assert_eq(summary["page"], "solisoft")
    assert_eq(summary["monitors"], PRODUCTION_SITES.length * 2)
    assert_eq(Monitor.count, PRODUCTION_SITES.length * 2)
    assert_eq(Component.where({"page_id": page._key}).count, PRODUCTION_SITES.length)
    assert_null(summary["user"])
  end

  test("a site's path and redirect setting reach its HTTP monitor") do
    ProductionSetup.run
    villa = Monitor.find_by("name", "Villa Vladimir")
    assert_eq(villa.url, "https://vv.solisoft.net/fr")
    assert_eq(villa.follow_redirects, false)
    assert_eq(Monitor.find_by("name", "Vitaliseur").follow_redirects, true)
    assert_eq(Monitor.find_by("name", "CSW admin").status_max, 401)
    assert_eq(Monitor.find_by("name", "Certificat grc.solisoft.net").kind, "tls")
  end

  test("a second run adds nothing and puts a changed monitor back in step") do
    ProductionSetup.run
    villa = Monitor.find_by("name", "Villa Vladimir")
    villa.url = "https://vv.solisoft.net/"
    villa.save
    ProductionSetup.run
    assert_eq(Monitor.count, PRODUCTION_SITES.length * 2)
    assert_eq(Component.count, PRODUCTION_SITES.length)
    assert_eq(Monitor.find_by("name", "Villa Vladimir").url, "https://vv.solisoft.net/fr")
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
