# Base for every admin screen: the admin layout and shared lookups. No actions.
# Its subclasses are reached only through `middleware("require_login", …)`.
class AdminController < Controller
  static {
    this.layout = "admin"
  }

  private

  # [[label, key]] for the monitor checkboxes of a form.
  def _monitor_choices
    Monitor.order("name").all.map { |monitor| {"id": monitor._key, "name": monitor.name, "kind": monitor.kind_label} }
  end

  # "2026-11-07T14:30" (a datetime-local field, UTC) → unix seconds; 0 if blank.
  def _unix_from_local(value)
    text = value.to_s.trim
    return 0 if text.blank?

    (DateTime.parse("#{text}:00Z") rescue DateTime.parse(text)).to_unix
  end

  def _local_from_unix(unix)
    return "" if unix.to_i == 0

    DateTime.from_unix(unix.to_i).format("%Y-%m-%dT%H:%M")
  end

  def _selected_ids(value)
    return [] if value.nil?
    return value.filter { |id| id.to_s.present? }.map { |id| id.to_s } if type(value) == "array"

    [value.to_s]
  end
end
