# Something went wrong: opened by the checker after N failures (kind "auto")
# or by a person (kind "manual"), with a timeline of updates.
#
# Fields: title, kind, status ("investigating" | "identified" | "monitoring" |
# "resolved"), impact ("degraded" | "outage"), monitor_ids (Array),
# started_at, resolved_at (unix s).
const INCIDENT_STATUSES = ["investigating", "identified", "monitoring", "resolved"]
const INCIDENT_IMPACTS = ["degraded", "outage"]

class Incident < Model
  validates("title", {"custom": "_validate"})
  before_save("normalize")

  def normalize
    @title = @title.to_s.trim
    @kind ||= "manual"
    @status = "investigating" if @status.blank?
    @impact = "outage" if @impact.blank?
    @monitor_ids ||= []
    @started_at ||= DateTime.utc.to_unix
    true
  end

  def open?
    @status != "resolved"
  end

  def status_label
    Incident.status_label(@status)
  end

  def impact_label
    @impact == "degraded" ? "Dégradation" : "Panne"
  end

  def updates
    IncidentUpdate.where({"incident_id": @_key}).order("at", "desc").all
  end

  # Moves the incident to `status` and writes the timeline entry for it.
  def post_update(status, message, now)
    @status = status
    @resolved_at = now if status == "resolved"
    @save
    IncidentUpdate.create({"incident_id": @_key, "status": status, "message": message, "at": now})
  end

  static def status_label(status)
    match status {
      "identified" => "Identifié",
      "monitoring" => "Sous surveillance",
      "resolved" => "Résolu",
      _ => "Enquête en cours"
    }
  end

  static def open_auto_for(monitor_id)
    Incident.where("doc.kind == 'auto' AND doc.status != 'resolved' AND @m IN doc.monitor_ids", {"m": monitor_id}).first
  end

  static def open_all
    Incident.where("doc.status != 'resolved'").order("started_at", "desc").all
  end

  static def touching(monitor_ids, limit)
    Incident.where("LENGTH(INTERSECTION(doc.monitor_ids, @ids)) > 0", {"ids": monitor_ids}).order("started_at", "desc").limit(limit).all
  end

  private

  def _validate
    errors = []
    errors.push({"field": "title", "message": "est obligatoire"}) if @title.to_s.trim.blank?
    errors.push({"field": "status", "message": "statut inconnu"}) unless @status.blank? || INCIDENT_STATUSES.includes?(@status)
    errors.push({"field": "impact", "message": "impact inconnu"}) unless @impact.blank? || INCIDENT_IMPACTS.includes?(@impact)
    errors.push({"field": "monitor_ids", "message": "choisissez au moins une sonde"}) if @monitor_ids.nil? || @monitor_ids.length == 0
    @_errors = (@_errors ?? []) + errors
    true
  end
end
