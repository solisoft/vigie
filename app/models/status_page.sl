# A public status page: /s/<slug>. Fields: slug, title, description, logo_url,
# published (Bool).
class StatusPage < Model
  validates("title", {"custom": "_validate"})
  before_save("normalize")

  def normalize
    @title = @title.to_s.trim
    @slug = @slug.to_s.trim.downcase
    @slug = @title.slugify if @slug.blank?
    @published = @published != false
    true
  end

  def components
    Component.where({"page_id": @_key}).order("position").all
  end

  private

  def _validate
    errors = []
    errors.push({"field": "title", "message": "est obligatoire"}) if @title.to_s.trim.blank?
    slug = @slug.to_s.trim.downcase
    slug = @title.to_s.slugify if slug.blank?
    errors.push({"field": "slug", "message": "lettres minuscules, chiffres et tirets"}) unless Regex.matches("^[a-z0-9][a-z0-9-]{0,62}$", slug)
    taken = StatusPage.find_by("slug", slug)
    errors.push({"field": "slug", "message": "déjà utilisé"}) if !taken.nil? && taken._key != @_key
    logo = @logo_url.to_s
    errors.push({"field": "logo_url", "message": "doit être une URL https:// ou un chemin /"}) unless logo.blank? || logo.starts_with?("https://") || logo.starts_with?("/")
    @_errors = (@_errors ?? []) + errors
    true
  end
end
