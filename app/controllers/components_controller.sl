# The services of a status page (components): what a visitor sees as one
# line, and the monitors that decide its state.
class ComponentsController < AdminController
  # POST /admin/pages/:id/composants — a new service from a name and an address
  def create
    page = StatusPage.find(params["id"])
    outcome = ServiceSetup.add(page, params["name"], params["url"], params["group_name"], params["position"])
    if outcome["errors"].length > 0
      messages = outcome["errors"].map do |error|
        error["message"]
      end
      flash("alert", "Service refusé : #{messages.join(", ")}")
      return redirect("/admin/pages/#{page._key}")
    end

    component = outcome["component"]
    flash("notice", "Service « #{component.name} » ajouté, avec #{component.monitor_ids.length} sonde(s).")
    redirect("/admin/composants/#{component._key}")
  end

  # GET /admin/composants/:id — the service, its monitors, what to add
  def edit
    @component = Component.find(params["id"])
    @_service_page
  end

  # PATCH /admin/composants/:id — name, group, order, description
  def update
    @component = Component.find(params["id"])
    @_attributes.each do |field, value|
      @component[field] = value
    end
    if Component.name_taken?(@component.name, @component._key)
      @component._errors = [{"field": "name", "message": "un service porte déjà ce nom (badge)"}]
    else
      @component.save
    end
    if @component._errors.length > 0
      @_service_page
      return render("components/edit", {}, {"status": 422})
    end

    flash("notice", "Service enregistré.")
    redirect("/admin/pages/#{this.component.page_id}")
  end

  # POST /admin/composants/:id/sondes — a new monitor of the chosen kind
  def add_monitor
    @component = Component.find(params["id"])
    @new_kind = params["kind"].to_s
    @new_form = permit(
      params,
      {
        "name": true,
        "url": true,
        "host": true,
        "port": true,
        "every_hours": true,
        "payload": true,
        "expect": true
      }
    )
    outcome = ServiceSetup.add_monitor(@component, @new_kind, @new_form)
    if outcome["errors"].length > 0
      @add_errors = outcome["errors"]
      @_service_page
      return render("components/edit", {}, {"status": 422})
    end

    flash("notice", "Sonde « #{outcome["monitor"].name} » ajoutée : premier contrôle dans quelques secondes.")
    redirect("/admin/composants/#{this.component._key}")
  end

  # DELETE /admin/composants/:id/sondes/:monitor_id — take a monitor off it;
  # deleted with its history unless another service still uses it
  def detach
    component = Component.find(params["id"])
    monitor = Monitor.find(params["monitor_id"].to_s)
    component.monitor_ids = component.monitor_ids.filter do |id|
      id != monitor._key
    end
    component.save
    if monitor.components.length == 0
      monitor.remove_with_history
      flash("notice", "Sonde « #{monitor.name} » supprimée.")
    else
      flash("notice", "Sonde « #{monitor.name} » retirée de ce service ; un autre service l'utilise encore.")
    end
    redirect("/admin/composants/#{component._key}")
  end

  # DELETE /admin/composants/:id — the service, and the monitors only it used
  def destroy
    component = Component.find(params["id"])
    component.delete
    removed = Monitor.where("doc._key IN @ids", {"ids": component.monitor_ids}).all.filter do |monitor|
      monitor.components.length == 0
    end
    removed.each do |monitor|
      monitor.remove_with_history
    end
    flash("notice", "Service retiré, avec #{removed.length} sonde(s) qu'il était seul à utiliser.")
    redirect("/admin/pages/#{component.page_id}")
  end

  private

  def _service_page
    @page = StatusPage.find(@component.page_id)
    @monitors = Monitor.where("doc._key IN @ids", {"ids": @component.monitor_ids}).order("name").all
    @service_host = @monitors.map do |monitor|
      ServiceSetup.host_of(monitor)
    end.compact.first
    @new_kind ||= "http"
    @default_url = @service_host.nil? ? "" : "https://#{this.service_host}/"
    @default_port = ["http", "tls"].includes?(@new_kind) ? 443 : nil
    @kind_options = [
      {
        "value": "http",
        "label": "Une adresse web",
        "hint": "répond, et vite"
      },
      {
        "value": "tls",
        "label": "Un certificat",
        "hint": "n'expire pas"
      },
      {
        "value": "tcp",
        "label": "Un port TCP",
        "hint": "accepte les connexions"
      },
      {
        "value": "udp",
        "label": "Un service UDP",
        "hint": "répond à un message"
      },
      {
        "value": "heartbeat",
        "label": "Une tâche planifiée",
        "hint": "prévient Vigie à chaque exécution"
      }
    ]
    @new_form ||= {}
    @add_errors ||= []
    @nav = "pages"
    @title = "Service « #{this.component.name} »"
    @description = "Un service de la page #{this.page.title}"
  end

  def _attributes
    attributes = permit(
      params,
      {
        "name": true,
        "description": true,
        "group_name": true,
        "position": true
      }
    )
    attributes["position"] = attributes["position"].to_s.to_i
    attributes
  end
end
