# Alert channels: e-mail, JSON webhook, Slack-compatible webhook.
class AlertChannelsController < AdminController
  # GET /admin/alertes — channels and the last deliveries
  def index
    @channels = AlertChannel.order("name").all
    @deliveries = AlertDelivery.order("at", "desc").limit(20).all
    @channel = AlertChannel.new({"kind": "email", "active": true})
    @_form_page
  end

  # POST /admin/alertes
  def create
    attributes = permit(params, {"name": true, "kind": true, "target": true, "active": true})
    attributes["active"] = attributes["active"].to_s == "true"
    @channel = AlertChannel.create(attributes)
    if @channel._errors
      @channels = AlertChannel.order("name").all
      @deliveries = AlertDelivery.order("at", "desc").limit(20).all
      @_form_page
      return render("alert_channels/index", {}, {"status": 422})
    end

    flash("notice", "Canal « #{@channel.name} » ajouté.")
    redirect("/admin/alertes")
  end

  # DELETE /admin/alertes/:id
  def destroy
    AlertChannel.find(params["id"]).delete
    flash("notice", "Canal supprimé.")
    redirect("/admin/alertes")
  end

  # POST /admin/alertes/:id/test — sends a test alert on this channel only
  def test
    channel = AlertChannel.find(params["id"])
    Alerts.deliver(channel, "test", {"title": "Vigie vous entend", "monitor": "test", "target": channel.target, "detail": "Ceci est une alerte de test.", "incident_id": nil})
    flash("notice", "Alerte de test envoyée à « #{channel.name} ».")
    redirect("/admin/alertes")
  end

  private

  def _form_page
    @kinds = [["E-mail", "email"], ["Webhook JSON", "webhook"], ["Slack (webhook entrant)", "slack"]]
    @nav = "alerts"
    @title = "Alertes"
    @description = "Où partent les alertes"
  end
end
