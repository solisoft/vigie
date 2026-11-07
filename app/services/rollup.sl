# Daily rollups and raw-check retention.
#
# `recompute` folds the raw checks since a timestamp into one DailyRollup per
# (monitor, day) in a single SDBQL statement — COLLECT + PERCENTILE + UPSERT —
# so the 7/30/90-day figures and the 90-day bars read at most 90 small rows
# per monitor and never touch the raw checks. Checks taken in a maintenance
# window are counted apart and stay out of the uptime.
class Rollup
  # Recomputes every day that has a check at or after `since` (unix s), whole
  # days: `since` is moved back to its midnight. → the rollup keys written.
  static def recompute(since)
    midnight = DateTime.parse(Checker.day_of(since)).to_unix
    rows = @sdbql{
      FOR c IN checks
        FILTER c.at >= #{midnight}
        COLLECT monitor_id = c.monitor_id, day = c.day
        AGGREGATE
          total = SUM(c.maintenance == true ? 0 : 1),
          up = SUM(c.maintenance != true AND c.ok == true ? 1 : 0),
          maintenance = SUM(c.maintenance == true ? 1 : 0),
          latencies = COLLECT_LIST(c.maintenance != true AND c.ok == true ? c.latency_ms : null)
        LET measured = FILTER(latencies, x -> x != null)
        LET rollup_key = CONCAT(monitor_id, "_", day)
        LET figures = {
          monitor_id, day, total, up, maintenance,
          p50_ms: LENGTH(measured) > 0 ? PERCENTILE(measured, 50) : null,
          p95_ms: LENGTH(measured) > 0 ? PERCENTILE(measured, 95) : null
        }
        UPSERT { _key: rollup_key }
        INSERT MERGE(figures, { _key: rollup_key })
        UPDATE figures
        IN daily_rollups
        RETURN rollup_key
    }
    Uptime.rows_or_raise(rows)
  end

  # Drops raw checks older than `days` days. → how many went.
  static def purge(now, days)
    cutoff = now - days * 86400
    stale = Check.where("doc.at < @cutoff", {"cutoff": cutoff})
    count = stale.count
    stale.delete_all
    count
  end

  static def retention_days
    configured = getenv("VIGIE_RAW_RETENTION_DAYS").to_s.to_i
    configured > 0 ? configured : 14
  end
end
