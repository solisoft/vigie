# Application-wide view helpers

# Absolute URL of `path` (starting with "/") for share tags: Open Graph,
# Twitter cards, the canonical link. From APP_URL (https://myapp.example.com),
# else the first of SOLI_APP_HOSTS over https; never from the request's Host
# header, which the client controls. Without either, it stays relative.
def absolute_url(path)
  base = getenv("APP_URL").to_s
  if base.blank?
    host = getenv("SOLI_APP_HOSTS").to_s.split(",").first.to_s.trim
    base = host.blank? ? "" : "https://" + host
  end
  base = base.substring(0, len(base) - 1) if base.ends_with?("/")
  base + path
end
