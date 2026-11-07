uptime_now = 1800000000

def uptime_reset
  [Check, DailyRollup].each do |model|
    model.all.each do |record|
      record.delete
    end
  end
end

def uptime_check(monitor_id, at, ok, latency_ms, maintenance)
  Check.create({
    "monitor_id": monitor_id,
    "at": at,
    "day": Checker.day_of(at),
    "status": ok ? "up" : "down",
    "ok": ok,
    "latency_ms": latency_ms,
    "maintenance": maintenance
  })
end

describe("Uptime math") do
  test("computes a percentage, nil without data") do
    assert_eq(Uptime.percent(999, 1000), 99.9)
    assert_eq(Uptime.percent(1, 3), 33.333)
    assert_null(Uptime.percent(0, 0))
  end

  test("grades a day: ok, partial, down, maintenance, none") do
    assert_eq(Uptime.level(1000, 1000, 0), "ok")
    assert_eq(Uptime.level(999, 1000, 0), "ok")
    assert_eq(Uptime.level(990, 1000, 0), "partial")
    assert_eq(Uptime.level(900, 1000, 0), "down")
    assert_eq(Uptime.level(0, 0, 12), "maintenance")
    assert_eq(Uptime.level(0, 0, 0), "none")
  end

  test("formats percentages the French way, never rounding a failure up to 100") do
    assert_eq(Uptime.format_percent(99.5), "99,5 %")
    assert_eq(Uptime.format_percent(99.999), "99,99 %")
    assert_eq(Uptime.format_percent(100.0), "100 %")
    assert_eq(Uptime.format_percent(nil), "—")
  end

  test("lists the last days, oldest first, today last") do
    days = Uptime.day_list("2026-03-02", 3)
    assert_eq(days, ["2026-02-28", "2026-03-01", "2026-03-02"])
    assert_eq(Uptime.french_day("2026-03-02"), "2 mars 2026")
  end

  test("builds 90 bars, summing monitors and filling the gaps with no data") do
    rows = [
      {"monitor_id": "a", "day": "2026-03-02", "total": 100, "up": 100, "maintenance": 0},
      {"monitor_id": "b", "day": "2026-03-02", "total": 100, "up": 90, "maintenance": 0},
      {"monitor_id": "a", "day": "2026-03-01", "total": 0, "up": 0, "maintenance": 5}
    ]
    bars = Uptime.bars(rows, "2026-03-02")
    assert_eq(bars.length, 90)
    assert_eq(bars[89]["level"], "down")
    assert_eq(bars[89]["percent"], 95.0)
    assert_eq(bars[89]["label"], "2 mars 2026 : Panne — 95 %")
    assert_eq(bars[88]["level"], "maintenance")
    assert_eq(bars[0]["level"], "none")
    assert_eq(bars[0]["label"], "3 déc. 2025 : Pas de données")
  end
end

describe("Rollups and windows in SoliDB") do
  before_each() do
    uptime_reset()
  end

  test("folds raw checks into one rollup per monitor and day, with p50/p95, maintenance apart") do
    yesterday = uptime_now - 86400
    (0..10).each do |i|
      uptime_check("m1", uptime_now + i, i != 3, (i + 1) * 10, false)
    end
    uptime_check("m1", uptime_now + 20, false, 5, true)
    uptime_check("m1", yesterday, true, 7, false)
    uptime_check("m2", uptime_now, true, 70, false)
    keys = Rollup.recompute(yesterday)
    assert_eq(keys.length, 3)
    today = DailyRollup.find("m1_2027-01-15")
    assert_eq(today.total, 10)
    assert_eq(today.up, 9)
    assert_eq(today.maintenance, 1)
    assert_eq(today.p50_ms, 60.0)
    assert_eq(today.p95_ms, 100.0)
    assert_eq(DailyRollup.find("m1_2027-01-14").total, 1)
  end

  test("recomputing is idempotent and picks up new checks") do
    uptime_check("m1", uptime_now, true, 10, false)
    Rollup.recompute(uptime_now)
    uptime_check("m1", uptime_now + 60, false, 10, false)
    Rollup.recompute(uptime_now)
    rollup = DailyRollup.find("m1_2027-01-15")
    assert_eq(rollup.total, 2)
    assert_eq(rollup.up, 1)
    assert_eq(DailyRollup.count, 1)
  end

  test("measures the last 24 h from raw checks, without maintenance") do
    uptime_check("m1", uptime_now - 100, true, 10, false)
    uptime_check("m1", uptime_now - 200, false, 10, false)
    uptime_check("m1", uptime_now - 300, false, 10, true)
    uptime_check("m1", uptime_now - 90000, false, 10, false)
    figures = Uptime.last_day(["m1", "absent"], uptime_now)
    assert_eq(figures["m1"]["total"], 2)
    assert_eq(figures["m1"]["up"], 1)
    assert_eq(figures["m1"]["p50_ms"], 10.0)
    assert_null(figures["absent"])
  end

  test("sums 7, 30 and 90 day windows from rollups") do
    DailyRollup.upsert("m1_2027-01-15", {"monitor_id": "m1", "day": "2027-01-15", "total": 100, "up": 100})
    DailyRollup.upsert("m1_2027-01-05", {"monitor_id": "m1", "day": "2027-01-05", "total": 100, "up": 50})
    DailyRollup.upsert("m1_2026-11-01", {"monitor_id": "m1", "day": "2026-11-01", "total": 100, "up": 0})
    DailyRollup.upsert("m1_2026-01-01", {"monitor_id": "m1", "day": "2026-01-01", "total": 100, "up": 0})
    windows = Uptime.windows(["m1"], "2027-01-15")["m1"]
    assert_eq([windows["t7"], windows["u7"]], [100, 100])
    assert_eq([windows["t30"], windows["u30"]], [200, 150])
    assert_eq([windows["t90"], windows["u90"]], [300, 150])
    rows = Uptime.daily(["m1"], "2027-01-15")
    assert_eq(rows.length, 3)
  end

  test("purges raw checks past the retention, keeping the rollups") do
    uptime_check("m1", uptime_now - 20 * 86400, true, 10, false)
    uptime_check("m1", uptime_now - 3600, true, 10, false)
    Rollup.recompute(uptime_now - 30 * 86400)
    assert_eq(Rollup.purge(uptime_now, 14), 1)
    assert_eq(Check.count, 1)
    assert_eq(DailyRollup.count, 2)
    assert_eq(Rollup.retention_days, 14)
  end

  test("an SDBQL error string is raised, not returned") do
    message = assert_raises() do
      Uptime.rows_or_raise("Error: Query failed: 400")
    end
    assert_contains(message, "SDBQL")
  end
end
