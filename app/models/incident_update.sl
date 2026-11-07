# One entry of an incident's timeline. Fields: incident_id, status, message, at.
class IncidentUpdate < Model
  def status_label
    Incident.label_for_status(@status)
  end
end
