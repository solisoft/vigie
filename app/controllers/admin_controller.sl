# Base for every admin screen: the admin layout and shared lookups. No actions.
# Its subclasses are reached only through `middleware("require_login", …)`.
class AdminController < Controller
  static {
    this.layout = "admin"
  }

  private

  # [[label, key]] for the monitor checkboxes of a form.
  def _monitor_choices
    Monitor.order("name").all.map do |monitor|
      {
        "id": monitor._key,
        "name": monitor.name,
        "kind": monitor.kind_label
      }
    end
  end

  # "2026-11-07T14:30" (a datetime-local field, UTC) → unix seconds; 0 if blank.
  def _unix_from_local(value)
    text = value.to_s.trim
    return 0 if text.blank?

    (DateTime.parse("#{text}:00Z") rescue DateTime.parse(text)).to_unix
  end

  def _local_from_unix(unix)
    return "" if unix.to_i == 0

    DateTime.from_unix(unix.to_i).to_iso.substring(0, 16)
  end

  def _selected_ids(value)
    return [] if value.nil?
    if type(value) == "array"
      return value.filter do |id|
        id.to_s.present?
      end.map do |id|
        id.to_s
      end
    end

    [value.to_s]
  end
end
