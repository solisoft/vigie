# Incidents: the automatic ones and those declared by hand, with their
# timeline of updates (investigating → identified → monitoring → resolved).
class IncidentsController < AdminController
  # GET /admin/incidents
  def index
    @open = Incident.open_all
    @recent = Incident.where({"status": "resolved"}).order("started_at", "desc").limit(30).all
    @nav = "incidents"
    @title = "Incidents"
    @description = "Incidents ouverts et résolus"
  end

  # GET /admin/incidents/nouveau
  def new
    @incident = Incident.new({"status": "investigating", "impact": "degraded"})
    @_form_page
  end

  # POST /admin/incidents — a manual incident and its first update
  def create
    attributes = permit(params, {"title": true, "status": true, "impact": true, "monitor_ids": []})
    attributes["monitor_ids"] = @_selected_ids(params["monitor_ids"])
    attributes["kind"] = "manual"
    attributes["started_at"] = DateTime.utc.to_unix
    @incident = Incident.create(attributes)
    if @incident._errors
      @_form_page
      return render("incidents/new", {}, {"status": 422})
    end

    message = params["message"].to_s.trim
    IncidentUpdate.create({"incident_id": @incident._key, "status": @incident.status, "message": message.blank? ? "Nous analysons la situation." : message, "at": @incident.started_at})
    Alerts.dispatch("incident.opened", @incident._key, {"title": @incident.title, "monitor": "déclaration manuelle", "target": "", "detail": message, "incident_id": @incident._key})
    sse_broadcast(LIVE_TOPIC, {"incident_id": @incident._key}.to_json, "status")
    flash("notice", "Incident publié.")
    redirect("/admin/incidents/#{@incident._key}")
  end

  # GET /admin/incidents/:id — the timeline and the form to add to it
  def show
    @incident = Incident.find(params["id"])
    @updates = @incident.updates
    @monitor_names = @_monitor_choices.index_by("id")
    @statuses = [["Enquête en cours", "investigating"], ["Identifié", "identified"], ["Sous surveillance", "monitoring"], ["Résolu", "resolved"]]
    @nav = "incidents"
    @title = @incident.title
    @description = @incident.status_label
  end

  # POST /admin/incidents/:id/suivis — a timeline entry; "resolved" closes it
  def add_update
    incident = Incident.find(params["id"])
    status = params["status"].to_s
    message = params["message"].to_s.trim
    unless INCIDENT_STATUSES.includes?(status) && message.present?
      flash("alert", "Choisissez un statut et écrivez un message.")
      return redirect("/admin/incidents/#{incident._key}")
    end

    was_open = incident.open?
    incident.post_update(status, message, DateTime.utc.to_unix)
    if was_open && status == "resolved"
      Alerts.dispatch("incident.resolved", incident._key, {"title": incident.title, "monitor": "déclaration manuelle", "target": "", "detail": message, "incident_id": incident._key})
    end
    sse_broadcast(LIVE_TOPIC, {"incident_id": incident._key}.to_json, "status")
    flash("notice", "Suivi publié.")
    redirect("/admin/incidents/#{incident._key}")
  end

  # DELETE /admin/incidents/:id
  def destroy
    incident = Incident.find(params["id"])
    IncidentUpdate.where({"incident_id": incident._key}).delete_all
    incident.delete
    flash("notice", "Incident supprimé.")
    redirect("/admin/incidents")
  end

  private

  def _form_page
    @monitor_choices = @_monitor_choices
    @statuses = [["Enquête en cours", "investigating"], ["Identifié", "identified"], ["Sous surveillance", "monitoring"]]
    @impacts = [["Dégradation", "degraded"], ["Panne", "outage"]]
    @nav = "incidents"
    @title = "Déclarer un incident"
    @description = "Un incident publié à la main"
  end
end
