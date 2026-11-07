# A planned window: its monitors show "maintenance", their failures open no
# incident and send no alert, and their checks stay out of the uptime figures.
#
# Fields: title, description, starts_at, ends_at (unix s), monitor_ids (Array).
class Maintenance < Model
  validates("title", {"custom": "_validate"})
  before_save("normalize")

  def normalize
    @title = @title.to_s.trim
    @monitor_ids ||= []
    @starts_at = @starts_at.to_i
    @ends_at = @ends_at.to_i
    true
  end

  def active_at?(now)
    @starts_at.to_i <= now && now < @ends_at.to_i
  end

  def upcoming_at?(now)
    @starts_at.to_i > now
  end

  def covers?(monitor_id)
    @monitor_ids.includes?(monitor_id)
  end

  static def active_at(now)
    Maintenance.where("doc.starts_at <= @now AND doc.ends_at > @now", {"now": now}).all
  end

  static def current_or_upcoming(now)
    Maintenance.where("doc.ends_at > @now", {"now": now}).order("starts_at").all
  end

  static def covering?(monitor_id, now)
    Maintenance.where(
      "doc.starts_at <= @now AND doc.ends_at > @now AND @m IN doc.monitor_ids",
      {"now": now, "m": monitor_id}
    ).count > 0
  end

  private

  def _validate
    errors = []
    if @title.to_s.trim.blank?
      errors.push({"field": "title", "message": "est obligatoire"})
    end
    if @starts_at.to_i <= 0
      errors.push({"field": "starts_at", "message": "date de début obligatoire"})
    end
    if @ends_at.to_i <= @starts_at.to_i
      errors.push({"field": "ends_at", "message": "doit suivre le début"})
    end
    @_errors = (@_errors ?? []) + errors
    true
  end
end
