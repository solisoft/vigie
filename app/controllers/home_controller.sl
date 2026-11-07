# The front door: the first published status page, or the way to the admin.
class HomeController < Controller
  static {
    this.layout = "status"
  }

  # GET / — redirects to the first published status page
  def index
    page = StatusPage.where({"published": true}).order("title").first
    return redirect("/s/#{page.slug}") unless page.nil?

    @title = "Vigie"
    @description = "Page de statut et surveillance de disponibilité, écrite en Soli."
  end

  # GET /health
  def health
    render_json({"status": "ok"})
  end
end
