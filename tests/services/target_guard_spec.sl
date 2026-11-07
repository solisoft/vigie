describe("TargetGuard") do
  test("reads the host out of a URL") do
    assert_eq(TargetGuard.host_of("https://user@Example.com:8443/x?y=1"), "example.com")
    assert_eq(TargetGuard.host_of("http://[::1]:80/"), "::1")
    assert_eq(TargetGuard.host_of("https://example.com"), "example.com")
    assert_eq(TargetGuard.host_of("http://[broken"), "")
  end

  test("accepts a public URL") do
    assert_null(TargetGuard.url_refusal("https://example.com/health", false))
  end

  test("refuses other schemes and a missing host") do
    assert_eq(TargetGuard.url_refusal("", false), "est obligatoire")
    assert_eq(TargetGuard.url_refusal("ftp://example.com", false), "doit commencer par http:// ou https://")
    assert_eq(TargetGuard.url_refusal("http:///nohost", false), "hôte manquant")
    assert_eq(TargetGuard.url_refusal("http://exa mple.com/", false), "caractères invalides dans l'hôte")
  end

  test("refuses loopback, private and link-local targets") do
    [
      "http://localhost/",
      "http://127.0.0.1:6745/",
      "http://10.1.2.3/",
      "http://172.16.0.1/",
      "http://172.31.255.1/",
      "http://192.168.1.1/",
      "http://169.254.169.254/latest/meta-data",
      "http://100.64.0.1/",
      "http://0.0.0.0/",
      "http://224.0.0.1/",
      "http://[::1]/",
      "http://[fd00::1]/",
      "http://[fe80::1]/",
      "http://[::ffff:10.0.0.1]/",
      "http://printer.local/",
      "http://db.internal/",
      "http://app.localhost/"
    ].each do |url|
      assert_eq(TargetGuard.url_refusal(url, false), "adresse privée ou locale refusée", url)
    end
  end

  test("keeps public neighbours of private ranges") do
    assert_null(TargetGuard.url_refusal("http://172.32.0.1/", false))
    assert_null(TargetGuard.url_refusal("http://8.8.8.8/", false))
    assert_null(TargetGuard.url_refusal("http://[2001:db8::1]/", false))
  end

  test("lets private targets through when the flag allows them") do
    assert_null(TargetGuard.url_refusal("http://127.0.0.1:9000/", true))
    assert_null(TargetGuard.host_refusal("localhost", true))
  end

  test("reads the flag from the environment (.env.test sets it)") do
    assert(TargetGuard.allow_private?)
  end
end
