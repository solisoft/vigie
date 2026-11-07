# The front door: what Vigie is, and the state of every published page.
class HomeController < Controller
  static {
    this.layout = "status"
  }

  # GET / — landing page: the pitch and the published pages not hidden from it
  def index
    now = DateTime.utc.to_unix
    @pages = StatusPage.where("doc.published == true AND doc.listed != false").order("title").all.map do |page|
      StatusBoard.summary(page, now)
    end
    @services = @pages.map do |summary|
      summary["services"]
    end.sum
    @title = "Vigie — page de statut et surveillance de disponibilité"
    @description = "Vigie sonde vos sites, certificats et tâches planifiées, ouvre les incidents "
    + "tout seul et publie une page de statut en direct."
  end

  # GET /health
  def health
    render_json({"status": "ok"})
  end
end
