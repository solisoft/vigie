# Monitors: list, create, edit, delete, and "check now".
class MonitorsController < AdminController
  # GET /admin/sondes
  def index
    @monitors = Monitor.order("name").all
    @nav = "monitors"
    @title = "Sondes"
    @description = "Les sondes HTTP, TLS et heartbeat"
  end

  # GET /admin/sondes/nouvelle
  def new
    @monitor = Monitor.new({
      "kind": params["kind"] || "http",
      "interval_s": 60,
      "failure_threshold": 2,
      "timeout_s": 10,
      "status_min": 200,
      "status_max": 399,
      "follow_redirects": true,
      "port": 443,
      "tls_warn_days": 14,
      "grace_s": 300,
      "http_method": "GET"
    })
    @_form_page("Nouvelle sonde")
  end

  # POST /admin/sondes
  def create
    @monitor = Monitor.create(Monitor.from_form(@_permitted))
    return @_render_form("new", "Nouvelle sonde") if @monitor._errors

    flash("notice", "Sonde « #{this.monitor.name} » créée : premier contrôle dans quelques secondes.")
    redirect("/admin/sondes/#{this.monitor._key}")
  end

  # GET /admin/sondes/:id — state, uptime, last checks
  def show
    @monitor = Monitor.find(params["id"])
    now = DateTime.utc.to_unix
    @board = DashboardBoard.row(
      @monitor,
      Maintenance.active_at(now).map(&{ |window|
        window.monitor_ids
      }).flatten,
      Uptime.last_day([@monitor._key], now)[@monitor._key] ?? {},
      Uptime.windows([@monitor._key], Checker.day_of(now))[@monitor._key] ?? {},
      Sparkline.recent([@monitor._key], now, 6)[@monitor._key] ?? []
    )
    @uptime = StatusBoard.uptime_figures(
      [@monitor._key],
      {"windows": Uptime.windows([@monitor._key], Checker.day_of(now)), "last_day": Uptime.last_day(
        [@monitor._key],
        now
      )}
    )
    @checks = Check.recent_for(@monitor._key, 30)
    @failures = Check.failures_for(@monitor._key, 50)
    @incidents = Incident.touching([@monitor._key], 10)
    @ping_url = "#{Alerts.base_url}/ping/#{this.monitor.heartbeat_token}"
    @nav = "monitors"
    @title = @monitor.name
    @description = @monitor.target_label
  end

  # GET /admin/sondes/:id/modifier
  def edit
    @monitor = Monitor.find(params["id"])
    @_form_page("Modifier « #{this.monitor.name} »")
  end

  # PATCH /admin/sondes/:id
  def update
    @monitor = Monitor.find(params["id"])
    Monitor.from_form(@_permitted).each do |field, value|
      @monitor[field] = value
    end
    @monitor.next_check_at = 0
    @monitor.save
    return @_render_form("edit", "Modifier « #{this.monitor.name} »") if @monitor._errors.length > 0

    flash("notice", "Sonde enregistrée.")
    redirect("/admin/sondes/#{this.monitor._key}")
  end

  # DELETE /admin/sondes/:id — the monitor and its raw checks
  def destroy
    monitor = Monitor.find(params["id"])
    Check.where({"monitor_id": monitor._key}).delete_all
    monitor.delete
    flash("notice", "Sonde supprimée.")
    redirect("/admin/sondes")
  end

  # POST /admin/sondes/:id/verifier — probe now, in the background
  def check_now
    monitor = Monitor.find(params["id"])
    CheckMonitorJob.perform_later(
      {"monitor_id": monitor._key},
      {"queue": "checks", "max_retries": 0}
    )
    flash("notice", "Contrôle lancé : le résultat arrive dans quelques secondes.")
    redirect("/admin/sondes/#{monitor._key}")
  end

  private

  def _permitted
    permit(
      params,
      {
        "name": true,
        "kind": true,
        "url": true,
        "http_method": true,
        "status_min": true,
        "status_max": true,
        "keyword": true,
        "follow_redirects": true,
        "timeout_s": true,
        "degraded_ms": true,
        "host": true,
        "port": true,
        "tls_warn_days": true,
        "grace_s": true,
        "interval_s": true,
        "failure_threshold": true,
        "paused": true
      }
    )
  end

  def _form_page(title)
    @nav = "monitors"
    @title = title
    @description = "Configuration d'une sonde"
    @kinds = [["HTTP(S)", "http"], ["Certificat TLS", "tls"], ["Heartbeat (cron)", "heartbeat"]]
    @methods = ["GET", "HEAD", "POST"]
  end

  def _render_form(view, title)
    @_form_page(title)
    render("monitors/#{view}", {}, {"status": 422})
  end
end
