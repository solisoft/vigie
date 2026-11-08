flow_monitor = nil
flow_now = 1800000000

def flow_reset
  [Check, Incident, IncidentUpdate, Maintenance, AlertChannel, AlertDelivery, Monitor].each do |model|
    model.all.each do |record|
      record.delete
    end
  end
end

def flow_result(status, error)
  {
    "status": status,
    "latency_ms": 42,
    "http_status": status == "down" ? 503 : 200,
    "error": error
  }
end

describe("Checker.next_status") do
  test("one failure leaves an up monitor up") do
    assert_eq(Checker.next_status("up", "down", 1, 2), "up")
  end

  test("the threshold-th failure turns it down") do
    assert_eq(Checker.next_status("up", "down", 2, 2), "down")
  end

  test("a never-checked monitor stays pending until confirmed") do
    assert_eq(Checker.next_status("pending", "down", 1, 2), "pending")
    assert_eq(Checker.next_status(nil, "down", 1, 3), "pending")
  end

  test("a down monitor stays down, and any success ends it") do
    assert_eq(Checker.next_status("down", "down", 5, 2), "down")
    assert_eq(Checker.next_status("down", "up", 0, 2), "up")
    assert_eq(Checker.next_status("down", "degraded", 0, 2), "degraded")
  end
end

describe("Incident state machine") do
  before_each() do
    flow_reset()
    flow_monitor = Monitor.create({
      "name": "API",
      "kind": "http",
      "url": "https://api.example.com/health",
      "interval_s": 60,
      "failure_threshold": 2
    })
    AlertChannel.create({
      "name": "Astreinte",
      "kind": "webhook",
      "target": "https://hooks.example.com/vigie",
      "active": true
    })
  end

  test("records each check with its day and verdict") do
    check = Checker.record(flow_monitor, flow_result("up", nil), flow_now)
    assert_eq(check.day, "2027-01-15")
    assert_eq(check.ok, true)
    assert_eq(Monitor.find(flow_monitor._key).status, "up")
    assert_eq(Monitor.find(flow_monitor._key).last_latency_ms, 42)
  end

  test("opens no incident on the first failure") do
    Checker.record(flow_monitor, flow_result("up", nil), flow_now)
    Checker.record(flow_monitor, flow_result("down", "HTTP 503"), flow_now + 60)
    assert_eq(Incident.count, 0)
    assert_eq(Monitor.find(flow_monitor._key).status, "up")
    assert_eq(Monitor.find(flow_monitor._key).consecutive_failures, 1)
  end

  test("opens one incident after N failures in a row, dated from the first one, and alerts once") do
    opened = Metrics.value("vigie.incidents.opened", {"kind": "http"}).to_i
    Checker.record(flow_monitor, flow_result("up", nil), flow_now)
    Checker.record(flow_monitor, flow_result("down", "HTTP 503"), flow_now + 60)
    Checker.record(flow_monitor, flow_result("down", "HTTP 503"), flow_now + 120)
    Checker.record(flow_monitor, flow_result("down", "HTTP 503"), flow_now + 180)
    assert_eq(Incident.count, 1)
    incident = Incident.all[0]
    assert_eq(incident.kind, "auto")
    assert_eq(incident.status, "investigating")
    assert_eq(incident.started_at, flow_now + 60)
    assert_eq(incident.monitor_ids, [flow_monitor._key])
    assert_contains(incident.updates[0].message, "2 échecs consécutifs")
    assert_eq(Monitor.find(flow_monitor._key).status, "down")
    assert_eq(AlertDelivery.where({"event": "incident.opened"}).count, 1)
    assert(Metrics.value("vigie.incidents.opened", {"kind": "http"}).to_i - opened >= 1)
  end

  test("resolves the incident on recovery, with a timeline entry and one alert") do
    Checker.record(flow_monitor, flow_result("down", "HTTP 503"), flow_now)
    Checker.record(flow_monitor, flow_result("down", "HTTP 503"), flow_now + 60)
    Checker.record(flow_monitor, flow_result("up", nil), flow_now + 660)
    Checker.record(flow_monitor, flow_result("up", nil), flow_now + 720)
    incident = Incident.all[0]
    assert_eq(incident.status, "resolved")
    assert_eq(incident.resolved_at.nil?, false)
    assert_eq(incident.updates.length, 2)
    assert_contains(incident.updates[0].message, "11 min")
    assert_eq(Monitor.find(flow_monitor._key).status, "up")
    assert_eq(AlertDelivery.where({"event": "incident.resolved"}).count, 1)
  end

  test("a new outage after recovery opens a new incident") do
    Checker.record(flow_monitor, flow_result("down", "x"), flow_now)
    Checker.record(flow_monitor, flow_result("down", "x"), flow_now + 60)
    Checker.record(flow_monitor, flow_result("up", nil), flow_now + 120)
    Checker.record(flow_monitor, flow_result("down", "x"), flow_now + 180)
    Checker.record(flow_monitor, flow_result("down", "x"), flow_now + 240)
    assert_eq(Incident.count, 2)
    assert_eq(Incident.open_all.length, 1)
    assert_eq(AlertDelivery.where({"event": "incident.opened"}).count, 2)
  end

  test("a maintenance window suppresses the incident and the alert, and flags the checks") do
    Maintenance.create({
      "title": "Migration",
      "starts_at": flow_now - 10,
      "ends_at": flow_now + 600,
      "monitor_ids": [flow_monitor._key]
    })
    Checker.record(flow_monitor, flow_result("down", "x"), flow_now)
    check = Checker.record(flow_monitor, flow_result("down", "x"), flow_now + 60)
    assert_eq(check.maintenance, true)
    assert_eq(Incident.count, 0)
    assert_eq(AlertDelivery.count, 0)
    assert_eq(Monitor.find(flow_monitor._key).status, "down")
  end

  test("a monitor still failing when the window closes opens the incident then") do
    Maintenance.create({
      "title": "Migration",
      "starts_at": flow_now - 10,
      "ends_at": flow_now + 100,
      "monitor_ids": [flow_monitor._key]
    })
    Checker.record(flow_monitor, flow_result("down", "x"), flow_now)
    Checker.record(flow_monitor, flow_result("down", "x"), flow_now + 60)
    Checker.record(flow_monitor, flow_result("down", "x"), flow_now + 120)
    assert_eq(Incident.count, 1)
    assert_eq(AlertDelivery.where({"event": "incident.opened"}).count, 1)
  end

  test("a maintenance of another monitor changes nothing") do
    Maintenance.create({
      "title": "Autre",
      "starts_at": flow_now - 10,
      "ends_at": flow_now + 600,
      "monitor_ids": ["someone-else"]
    })
    Checker.record(flow_monitor, flow_result("down", "x"), flow_now)
    Checker.record(flow_monitor, flow_result("down", "x"), flow_now + 60)
    assert_eq(Incident.count, 1)
  end

  test("emits check metrics tagged by kind and status") do
    # Metrics are shared by the specs running in parallel: compare before and
    # after, and count at least what this test recorded.
    ups = Metrics.value(
      "vigie.checks",
      {"kind": "http", "status": "up"}
    ).to_i
    downs = Metrics.value(
      "vigie.checks",
      {"kind": "http", "status": "down"}
    ).to_i
    latencies = (Metrics.value("vigie.check.latency", {"kind": "http"}) ?? {})["count"].to_i
    Checker.record(flow_monitor, flow_result("up", nil), flow_now)
    Checker.record(flow_monitor, flow_result("down", "x"), flow_now + 60)
    assert(Metrics.value(
      "vigie.checks",
      {"kind": "http", "status": "up"}
    ).to_i - ups >= 1)
    assert(Metrics.value(
      "vigie.checks",
      {"kind": "http", "status": "down"}
    ).to_i - downs >= 1)
    assert(Metrics.value("vigie.check.latency", {"kind": "http"})["count"].to_i - latencies >= 2)
  end
end

describe("Certificate expiry alerts") do
  before_each() do
    flow_reset()
    flow_monitor = Monitor.create({
      "name": "Certificat",
      "kind": "tls",
      "host": "example.com",
      "port": 443,
      "interval_s": 3600,
      "tls_warn_days": 14
    })
    AlertChannel.create({
      "name": "Slack",
      "kind": "slack",
      "target": "https://hooks.slack.example.com/T/B/x",
      "active": true
    })
  end

  test("alerts once per certificate under the threshold") do
    soon = {
      "status": "degraded",
      "latency_ms": 30,
      "http_status": nil,
      "error": "Le certificat expire dans 5 j",
      "tls_days_left": 5,
      "tls_not_after": "2027-01-20T00:00:00Z"
    }
    Checker.record(flow_monitor, soon, flow_now)
    Checker.record(flow_monitor, soon, flow_now + 3600)
    assert_eq(AlertDelivery.where({"event": "tls.expiring"}).count, 1)
    assert_eq(Monitor.find(flow_monitor._key).tls_days_left, 5)
    renewed_then_soon = soon.merge({"tls_not_after": "2027-04-20T00:00:00Z"})
    Checker.record(flow_monitor, renewed_then_soon, flow_now + 7200)
    assert_eq(AlertDelivery.where({"event": "tls.expiring"}).count, 2)
  end

  test("stays quiet above the threshold") do
    fine = {
      "status": "up",
      "latency_ms": 30,
      "http_status": nil,
      "error": nil,
      "tls_days_left": 60,
      "tls_not_after": "2027-03-16T00:00:00Z"
    }
    Checker.record(flow_monitor, fine, flow_now)
    assert_eq(AlertDelivery.count, 0)
  end
end
