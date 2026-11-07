# Where alerts go. Fields: name, kind ("email" | "webhook" | "slack"), target
# (an address or an https URL), active (Bool), tls_warn_days.
const ALERT_KINDS = ["email", "webhook", "slack"]

class AlertChannel < Model
  validates("name", {"custom": "_validate"})
  before_save("normalize")

  def normalize
    @name = @name.to_s.trim
    @target = @target.to_s.trim
    @active = @active != false
    true
  end

  def kind_label
    match @kind {
      "email" => "E-mail",
      "slack" => "Slack",
      _ => "Webhook JSON",
    }
  end

  private

  def _validate
    errors = []
    if @name.to_s.trim.blank?
      errors.push({"field": "name", "message": "est obligatoire"})
    end
    unless ALERT_KINDS.includes?(@kind.to_s)
      errors.push({"field": "kind", "message": "type inconnu"})
    end
    target = @target.to_s.trim
    if @kind == "email"
      unless Regex.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", target)
        errors.push({"field": "target", "message": "adresse e-mail invalide"})
      end
    else
      refusal = TargetGuard.url_refusal(target, TargetGuard.allow_private?)
      unless refusal.nil?
        errors.push({"field": "target", "message": refusal})
      end
    end
    @_errors = (@_errors ?? []) + errors
    true
  end
end
