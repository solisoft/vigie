# Refuses monitor targets on loopback, private or link-local addresses (SSRF).
#
# Only the literal host is judged here — a name that *resolves* to a private
# address is stopped by Soli's own HTTP/X509 guard at request time. This layer
# gives the admin a readable refusal when the monitor is saved.
# VIGIE_ALLOW_PRIVATE_TARGETS=1 lifts it (demo seed, a lab); Soli's guard then
# also needs SOLI_HTTP_ALLOW_HOSTS (or SOLI_DEV_ALLOW_SSRF=1) to let the probe out.
const PRIVATE_SUFFIXES = [
  ".localhost",
  ".local",
  ".internal",
  ".lan",
  ".home.arpa"
]

class TargetGuard
  static def allow_private?
    getenv("VIGIE_ALLOW_PRIVATE_TARGETS").to_s == "1"
  end

  # nil when the URL may be probed, else a French message.
  static def url_refusal(url, allow_private)
    return "est obligatoire" if url.blank?

    lowered = url.downcase
    unless lowered.starts_with?("http://") || lowered.starts_with?("https://")
      return "doit commencer par http:// ou https://"
    end

    host = TargetGuard.host_of(url)
    return "hôte manquant" if host.blank?

    TargetGuard.host_refusal(host, allow_private)
  end

  static def host_refusal(host, allow_private)
    return "est obligatoire" if host.blank?
    return "caractères invalides dans l'hôte" unless Regex.matches("^[a-z0-9.:\\-\\[\\]]+$", host)
    return nil if allow_private
    return "adresse privée ou locale refusée" if TargetGuard.private_host?(host)

    nil
  end

  # "https://user@Example.com:8443/x?y" → "example.com"; "[::1]:80" → "::1".
  static def host_of(url)
    rest = url
    scheme_end = rest.index_of("://")
    rest = rest.substring(scheme_end + 3, rest.length) if scheme_end >= 0
    ["/", "?", "#"].each do |separator|
      position = rest.index_of(separator)
      rest = rest.substring(0, position) if position >= 0
    end
    at = rest.index_of("@")
    rest = rest.substring(at + 1, rest.length) if at >= 0
    if rest.starts_with?("[")
      closing = rest.index_of("]")
      return rest.substring(1, closing).downcase if closing > 0

      return ""
    end
    colon = rest.index_of(":")
    rest = rest.substring(0, colon) if colon >= 0
    rest.downcase
  end

  static def private_host?(host)
    bare = host.delete_prefix("[").delete_suffix("]")
    return true if bare == "localhost" || bare == "0" || bare.blank?
    if PRIVATE_SUFFIXES.any?(&{ |suffix|
      bare.ends_with?(suffix)
    })
      return true
    end

    return TargetGuard.private_ipv6?(bare) if bare.includes?(":")

    TargetGuard.private_ipv4?(bare)
  end

  static def private_ipv4?(host)
    return false unless Regex.matches("^[0-9]+(\\.[0-9]+){3}$", host)

    octets = host.split(".").map do |part|
      part.to_i
    end
    first = octets[0]
    second = octets[1]
    return true if [0, 10, 127].includes?(first)
    return true if first == 169 && second == 254
    return true if first == 172 && second >= 16 && second <= 31
    return true if first == 192 && second == 168
    return true if first == 100 && second >= 64 && second <= 127
    return true if first >= 224

    false
  end

  static def private_ipv6?(host)
    return true if ["::", "::1"].includes?(host)
    return true if host.starts_with?("fc") || host.starts_with?("fd") || host.starts_with?("fe80")
    return TargetGuard.private_ipv4?(host.delete_prefix("::ffff:")) if host.starts_with?("::ffff:")

    false
  end
end
