# The alert e-mail: same words as the webhooks, as text and HTML.
class AlertMailer < Mailer
  def notify(address, subject, body)
    @body_lines = body.split("\n")
    this.mail(to: address, subject: subject, text: body)
  end
end
