# Uptime and latency figures, computed in SoliDB.
#
# 24 h comes from the raw checks (one COLLECT … AGGREGATE); 7, 30 and 90 days
# come from the daily rollups — one more COLLECT over at most 90 rows per
# monitor. Checks taken during maintenance are not counted.
const UPTIME_OK = 99.9
const UPTIME_PARTIAL = 98.0
const BAR_DAYS = 90

class Uptime
  # monitor_id → {"total", "up", "p50_ms", "p95_ms"} over the 24 h before `now`.
  static def last_day(monitor_ids, now)
    since = now - 86400
    rows = @sdbql{
      FOR c IN checks
        FILTER c.at >= #{since} AND c.monitor_id IN #{monitor_ids} AND c.maintenance != true
        COLLECT monitor_id = c.monitor_id
        AGGREGATE total = COUNT(), up = SUM(c.ok == true ? 1 : 0),
          latencies = COLLECT_LIST(c.ok == true ? c.latency_ms : null)
        LET measured = FILTER(latencies, x -> x != null)
        RETURN {
          monitor_id, total, up,
          p50_ms: LENGTH(measured) > 0 ? PERCENTILE(measured, 50) : null,
          p95_ms: LENGTH(measured) > 0 ? PERCENTILE(measured, 95) : null
        }
    }
    Uptime.index_rows(Uptime.rows_or_raise(rows))
  end

  # monitor_id → {"t7", "u7", "t30", "u30", "t90", "u90"} from the rollups.
  static def windows(monitor_ids, today)
    day7 = Uptime.days_back(today, 6)
    day30 = Uptime.days_back(today, 29)
    day90 = Uptime.days_back(today, 89)
    rows = @sdbql{
      FOR r IN daily_rollups
        FILTER r.monitor_id IN #{monitor_ids} AND r.day >= #{day90}
        COLLECT monitor_id = r.monitor_id
        AGGREGATE
          t7 = SUM(r.day >= #{day7} ? r.total : 0), u7 = SUM(r.day >= #{day7} ? r.up : 0),
          t30 = SUM(r.day >= #{day30} ? r.total : 0), u30 = SUM(r.day >= #{day30} ? r.up : 0),
          t90 = SUM(r.total), u90 = SUM(r.up)
        RETURN { monitor_id, t7, u7, t30, u30, t90, u90 }
    }
    Uptime.index_rows(Uptime.rows_or_raise(rows))
  end

  # The rollup rows of the last BAR_DAYS days, projected to what a bar needs.
  static def daily(monitor_ids, today)
    first_day = Uptime.days_back(today, BAR_DAYS - 1)
    rows = @sdbql{
      FOR r IN daily_rollups
        FILTER r.monitor_id IN #{monitor_ids} AND r.day >= #{first_day}
        RETURN { monitor_id: r.monitor_id, day: r.day, total: r.total, up: r.up, maintenance: r.maintenance }
    }
    Uptime.rows_or_raise(rows)
  end

  # Sums rows (several monitors, same day) into one bar per day, oldest first.
  static def bars(rows, today)
    by_day = rows.group_by("day")
    Uptime.day_list(today, BAR_DAYS).map do |day|
      day_rows = by_day[day] ?? []
      total = day_rows.map { |row| row["total"].to_i }.sum
      up = day_rows.map { |row| row["up"].to_i }.sum
      maintenance = day_rows.map { |row| row["maintenance"].to_i }.sum
      level = Uptime.level(up, total, maintenance)
      {
        "day": day,
        "level": level,
        "percent": Uptime.percent(up, total),
        "label": Uptime.bar_label(day, level, up, total)
      }
    end
  end

  static def percent(up, total)
    return nil if total.to_i == 0

    (up.to_f * 100.0 / total.to_f).round(3)
  end

  static def level(up, total, maintenance)
    if total.to_i == 0
      return maintenance.to_i > 0 ? "maintenance" : "none"
    end

    ratio = Uptime.percent(up, total)
    return "ok" if ratio >= UPTIME_OK
    return "partial" if ratio >= UPTIME_PARTIAL

    "down"
  end

  static def level_label(level)
    match level {
      "ok" => "Opérationnel",
      "partial" => "Perturbations",
      "down" => "Panne",
      "maintenance" => "Maintenance",
      _ => "Pas de données"
    }
  end

  static def bar_label(day, level, up, total)
    figure = total.to_i > 0 ? " — #{Uptime.format_percent(Uptime.percent(up, total))}" : ""
    "#{Uptime.french_day(day)} : #{Uptime.level_label(level)}#{figure}"
  end

  # 99.95 → "99,95 %", nil → "—"
  static def format_percent(value)
    return "—" if value.nil?

    shown = value >= 99.995 && value < 100 ? 99.99 : value.round(2)
    "#{shown.to_s.replace(".", ",")} %"
  end

  static def french_day(day)
    parts = day.split("-")
    months = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
    "#{parts[2].to_i} #{months[parts[1].to_i - 1]} #{parts[0]}"
  end

  static def day_list(today, count)
    (0..count).map { |i| Uptime.days_back(today, count - 1 - i) }
  end

  static def days_back(today, days)
    DateTime.parse(today).add_days(-days).format("%Y-%m-%d")
  end

  static def index_rows(rows)
    indexed = {}
    rows.each do |row|
      indexed[row["monitor_id"]] = row
    end
    indexed
  end

  # An @sdbql block answers a String on a failed query instead of raising.
  static def rows_or_raise(rows)
    throw "SDBQL : #{rows}" if type(rows) == "string"

    rows
  end
end
