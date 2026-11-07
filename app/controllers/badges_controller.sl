# SVG status badges: /badge/<component-slug>.svg
class BadgesController < Controller
  # GET /badge/:file — e.g. /badge/api.svg
  def show
    file = params["file"].to_s
    halt(404, "Badge introuvable") unless file.ends_with?(".svg")

    component = Component.find_by("slug", file.delete_suffix(".svg"))
    halt(404, "Badge introuvable") if component.nil?

    page = StatusPage.find(component.page_id)
    halt(404, "Badge introuvable") unless page.published

    board = StatusBoard.build(page, DateTime.utc.to_unix)
    row = board["components"].find { |candidate| candidate["slug"] == component.slug }
    {
      "status": 200,
      "headers": {"Content-Type": "image/svg+xml; charset=utf-8", "Cache-Control": "public, max-age=60"},
      "body": BadgeSvg.render(component.name, row["status"], row["status_label"].downcase)
    }
  end
end
