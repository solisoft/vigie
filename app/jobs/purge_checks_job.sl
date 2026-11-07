# Every night: drops raw checks older than VIGIE_RAW_RETENTION_DAYS (14 by
# default). The daily rollups keep the history the status page shows.
class PurgeChecksJob
  static cron: String = Cron.daily_at("03:30")

  static def perform(args: Hash)
    now = DateTime.utc.to_unix
    Rollup.recompute(now - 86400)
    Rollup.purge(now, Rollup.retention_days)
  end
end
