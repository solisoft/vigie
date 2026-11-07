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

  # The services to tick on an incident or a maintenance, page by page; one
  # box stands for all the monitors of its service. The monitors on no page
  # come last, one box each.
  # -> [{"title", "items": [{"label", "detail", "value", "ids"}]}]
  def _service_choices
    monitors = []
    pages = []
    components = []
    grouped(fn() {
      monitors = Monitor.order("name").all
      pages = StatusPage.order("title").all
      components = Component.order("position").all
    })
    ServiceSetup.sections(pages, components, monitors).map do |section|
      items = section["services"].map do |service|
        if service["component"].nil?
          service["monitors"].map do |monitor|
            {
              "label": monitor.name,
              "detail": monitor.kind_label,
              "value": monitor._key,
              "ids": [monitor._key]
            }
          end
        else
          ids = service["monitors"].map(&:_key)
          [{
            "label": service["component"].name,
            "detail": "#{ids.length} sonde(s)",
            "value": ids.join(","),
            "ids": ids
          }]
        end
      end.flatten.filter do |item|
        item["ids"].length > 0
      end
      {"title": section["title"], "items": items}
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
      return value.map do |id|
        id.to_s.split(",")
      end.flatten.map(&:trim).filter do |id|
        id.present?
      end.uniq
    end

    value.to_s.split(",").map(&:trim).filter do |id|
      id.present?
    end
  end
end
