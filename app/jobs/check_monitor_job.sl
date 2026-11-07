# Probes one monitor and records the result (see Checker).
class CheckMonitorJob
  static def perform(args: Hash)
    monitor = Monitor.find_by("_key", args["monitor_id"])
    return nil if monitor.nil? || monitor.paused

    recorded_check = Checker.run(monitor, DateTime.utc.to_unix)
    recorded_check&.status
  end
end
