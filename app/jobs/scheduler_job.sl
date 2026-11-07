# Every 15 seconds: hands each due monitor to a CheckMonitorJob, so probes
# run in parallel on the job workers (SOLI_JOB_WORKERS) and a slow target
# never delays the others.
class SchedulerJob
  static cron: String = "*/15 * * * * *"

  static def perform(args: Hash)
    now = DateTime.utc.to_unix
    due = SchedulerJob.due_monitors(now)
    due.each do |monitor|
      monitor.next_check_at = now + monitor.interval_s
      monitor.save
      CheckMonitorJob.perform_later(
        {"monitor_id": monitor._key},
        {"queue": "checks", "max_retries": 0}
      )
    end
    Metrics.gauge("vigie.monitors.down", Monitor.where({
      "status": "down",
      "paused": false
    }).count)
    due.length
  end

  static def due_monitors(now)
    Monitor.where("doc.paused != true AND doc.next_check_at <= @now", {"now": now}).all
  end
end
