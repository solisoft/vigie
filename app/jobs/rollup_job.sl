# Every 5 minutes: refreshes today's and yesterday's daily rollups.
class RollupJob
  static cron: String = Cron.every("5 minutes")

  static def perform(args: Hash)
    now = DateTime.utc.to_unix
    Rollup.recompute(now - 86400).length
  end
end
