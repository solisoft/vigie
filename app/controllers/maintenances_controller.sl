# Planned maintenance windows: shown on the pages, alerts held back.
class MaintenancesController < AdminController
  # GET /admin/maintenances
  def index
    now = DateTime.utc.to_unix
    @now = now
    @upcoming = Maintenance.current_or_upcoming(now)
    @past = Maintenance.where("doc.ends_at <= @now", {"now": now}).order("starts_at", "desc").limit(20).all
    @nav = "maintenances"
    @title = "Maintenances"
    @description = "Fenêtres de maintenance planifiées"
  end

  # GET /admin/maintenances/nouvelle
  def new
    start = (DateTime.utc.to_unix / 3600 + 1) * 3600
    @maintenance = Maintenance.new({"starts_at": start, "ends_at": start + 3600, "monitor_ids": []})
    @_form_page("Planifier une maintenance")
  end

  # POST /admin/maintenances
  def create
    @maintenance = Maintenance.create(@_attributes)
    return @_render_form("new", "Planifier une maintenance") if @maintenance._errors

    sse_broadcast(LIVE_TOPIC, {"maintenance_id": @maintenance._key}.to_json, "status")
    flash("notice", "Maintenance planifiée.")
    redirect("/admin/maintenances")
  end

  # GET /admin/maintenances/:id
  def edit
    @maintenance = Maintenance.find(params["id"])
    @_form_page("Modifier la maintenance")
  end

  # PATCH /admin/maintenances/:id
  def update
    @maintenance = Maintenance.find(params["id"])
    @_attributes.each do |field, value|
      @maintenance[field] = value
    end
    @maintenance.save
    return @_render_form("edit", "Modifier la maintenance") if @maintenance._errors.length > 0

    sse_broadcast(LIVE_TOPIC, {"maintenance_id": @maintenance._key}.to_json, "status")
    flash("notice", "Maintenance enregistrée.")
    redirect("/admin/maintenances")
  end

  # DELETE /admin/maintenances/:id
  def destroy
    Maintenance.find(params["id"]).delete
    sse_broadcast(LIVE_TOPIC, "{}", "status")
    flash("notice", "Maintenance supprimée.")
    redirect("/admin/maintenances")
  end

  private

  def _attributes
    attributes = permit(params, {"title": true, "description": true, "monitor_ids": []})
    attributes["monitor_ids"] = @_selected_ids(params["monitor_ids"])
    attributes["starts_at"] = @_unix_from_local(params["starts_at_local"])
    attributes["ends_at"] = @_unix_from_local(params["ends_at_local"])
    attributes
  end

  def _form_page(title)
    @starts_local = @_local_from_unix(@maintenance.starts_at)
    @ends_local = @_local_from_unix(@maintenance.ends_at)
    @monitor_choices = @_monitor_choices
    @nav = "maintenances"
    @title = title
    @description = "Une fenêtre de maintenance"
  end

  def _render_form(view, title)
    @_form_page(title)
    render("maintenances/#{view}", {}, {"status": 422})
  end
end
