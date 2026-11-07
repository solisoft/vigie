# The admin dashboard: every monitor at a glance, live.
class DashboardController < AdminController
  # GET /admin — monitors, their state, uptime and latency sparklines
  def show
    @board = DashboardBoard.build(DateTime.utc.to_unix)
    @nav = "dashboard"
    @title = "Tableau de bord"
    @description = "État de toutes les sondes"
  end

  # GET /admin/live — Server-Sent Events for the dashboard
  def live
    sse_subscribe(req, LIVE_TOPIC)
  end
end
