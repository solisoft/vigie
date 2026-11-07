# A public status page: /s/<slug>. Fields: slug, title, description, logo_url,
# published (Bool).
class StatusPage < Model
  validates("title", {"custom": "_validate"})
  # A custom validator sees no _key on update (Soli 2.32), so "unique except
  # myself" is checked here on create and by the controller on update.
  validates(
    "slug",
    {"custom": "_slug_free", "on": "create"}
  )
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

  static def slug_taken?(slug, own_key)
    taken = StatusPage.find_by("slug", slug)
    !taken.nil? && taken._key != own_key
  end

  private

  def _slug_free
    slug = @slug.to_s.trim.downcase
    slug = @title.to_s.slugify if slug.blank?
    return "déjà utilisé" if StatusPage.slug_taken?(slug, nil)

    true
  end

  def _validate
    errors = []
    if @title.to_s.trim.blank?
      errors.push({"field": "title", "message": "est obligatoire"})
    end
    slug = @slug.to_s.trim.downcase
    slug = @title.to_s.slugify if slug.blank?
    unless Regex.matches("^[a-z0-9][a-z0-9-]{0,62}$", slug)
      errors.push({"field": "slug", "message": "lettres minuscules, chiffres et tirets"})
    end
    logo = @logo_url.to_s
    unless logo.blank? || logo.starts_with?("https://") || logo.starts_with?("/")
      errors.push({"field": "logo_url", "message": "doit être une URL https:// ou un chemin /"})
    end
    @_errors = (@_errors ?? []) + errors
    true
  end
end
