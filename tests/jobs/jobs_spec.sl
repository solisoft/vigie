jobs_base = ""

def jobs_reset
  [Check, DailyRollup, Incident, IncidentUpdate, Monitor].each do |model|
    model.all.each do |record|
      record.delete
    end
  end
end

describe("SchedulerJob") do
  before_all() do
    port = mock_http_server_start()
    jobs_base = "http://127.0.0.1:" + port.to_s
    mock_http_route("/jobs/ok", 200, "ok")
  end

  before_each() do
    jobs_reset()
  end

  test("picks due monitors, pushes their next check, skips paused and future ones") do
    now = DateTime.utc.to_unix
    due = Monitor.create({
      "name": "Due",
      "url": jobs_base + "/jobs/ok",
      "interval_s": 60
    })
    Monitor.create({
      "name": "Later",
      "url": jobs_base + "/jobs/ok",
      "interval_s": 60,
      "next_check_at": now + 500
    })
    Monitor.create({
      "name": "Paused",
      "url": jobs_base + "/jobs/ok",
      "interval_s": 60,
      "paused": true
    })
    assert_eq(SchedulerJob.perform_now({}), 1)
    pushed = Monitor.find(due._key).next_check_at
    assert(pushed >= now + 60)
    assert_eq(SchedulerJob.perform_now({}), 0)
  end
end

describe("CheckMonitorJob") do
  before_each() do
    jobs_reset()
  end

  test("probes the monitor and records the check") do
    monitor = Monitor.create({
      "name": "Job",
      "url": jobs_base + "/jobs/ok",
      "interval_s": 60
    })
    assert_eq(CheckMonitorJob.perform_now({"monitor_id": monitor._key}), "up")
    assert_eq(Check.where({"monitor_id": monitor._key}).count, 1)
    assert_eq(Monitor.find(monitor._key).status, "up")
  end

  test("does nothing for a paused or deleted monitor") do
    paused = Monitor.create({
      "name": "Paused",
      "url": jobs_base + "/jobs/ok",
      "interval_s": 60,
      "paused": true
    })
    assert_null(CheckMonitorJob.perform_now({"monitor_id": paused._key}))
    assert_null(CheckMonitorJob.perform_now({"monitor_id": "gone"}))
    assert_eq(Check.count, 0)
  end

  test("records nothing for a heartbeat still in its first window") do
    beat = Monitor.create({
      "name": "Cron",
      "kind": "heartbeat",
      "interval_s": 300
    })
    assert_null(CheckMonitorJob.perform_now({"monitor_id": beat._key}))
    assert_eq(Check.count, 0)
  end
end

describe("RollupJob and PurgeChecksJob") do
  before_each() do
    jobs_reset()
  end

  test("roll up today's checks, then purge old raw ones") do
    now = DateTime.utc.to_unix
    Check.create({
      "monitor_id": "m",
      "at": now,
      "day": Checker.day_of(now),
      "ok": true,
      "latency_ms": 12,
      "maintenance": false
    })
    Check.create({
      "monitor_id": "m",
      "at": now - 40 * 86400,
      "day": Checker.day_of(now - 40 * 86400),
      "ok": true,
      "latency_ms": 12,
      "maintenance": false
    })
    assert_eq(RollupJob.perform_now({}), 1)
    assert_eq(PurgeChecksJob.perform_now({}), 1)
    assert_eq(Check.count, 1)
  end
end

describe("Check metrics") do
  test("a run is timed, and its latency recorded in seconds") do
    jobs_reset()
    Metrics.reset
    monitor = Monitor.create({
      "name": "Timed",
      "url": jobs_base + "/jobs/ok",
      "interval_s": 60
    })
    Checker.run(monitor, DateTime.utc.to_unix)
    assert_eq(Metrics.value("vigie.check.duration", {"kind": "http"})["count"], 1)
    latency = Metrics.value("vigie.check.latency", {"kind": "http"})
    assert_eq(latency["count"], 1)
    assert(latency["sum"] < 5.0)
  end
end
