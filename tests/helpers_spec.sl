describe("Vigie view helpers") do
  test("write dates in French, in UTC") do
    assert_eq(french_time(1800000000), "15 janv. 2027, 08:00 UTC")
    assert_eq(french_date(1800000000), "15 janv. 2027")
    assert_eq(iso_time(1800000000), "2027-01-15T08:00:00Z")
    assert_eq(french_time(nil), "—")
    assert_eq(french_date(0), "—")
  end

  test("format percentages and latencies") do
    assert_eq(percent_label(99.987), "99,99 %")
    assert_eq(percent_label(99.999), "99,99 %")
    assert_eq(percent_label(nil), "—")
    assert_eq(latency_label(123.6), "124 ms")
    assert_eq(latency_label(80), "80 ms")
    assert_eq(latency_label(nil), "—")
  end

  test("name every status in words, with an icon") do
    ["up", "degraded", "down", "maintenance", "paused", "pending"].each do |status|
      assert(status_text(status).present?)
    end
    assert_eq(status_text("paused"), "En pause")
    ["up", "ok", "degraded", "partial", "down", "major", "maintenance", "pending"].each do |status|
      assert_contains(status_icon(status), "aria-hidden=\"true\"")
    end
  end

  test("build absolute URLs from APP_URL") do
    assert_eq(absolute_url("/s/demo"), "http://localhost:5099/s/demo")
  end
end
