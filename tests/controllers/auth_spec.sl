auth_user = nil

def auth_reset
  User.all.each do |record|
    record.delete
  end
  auth_user = User.new()
  auth_user.email = "veille@vigie.example"
  auth_user.set_password("a long enough passphrase")
  auth_user.save
  as_guest()
end

describe("Password reset") do
  before_each() do
    auth_reset()
  end

  test("asks for an address and never says whether it exists") do
    assert_contains(res_body(get("/password/reset")), "Mot de passe oublié")
    known = post("/password/reset", {"email": "veille@vigie.example"})
    unknown = post("/password/reset", {"email": "personne@vigie.example"})
    assert_contains(res_body(known), "Si ce compte existe")
    assert_contains(res_body(unknown), "Si ce compte existe")
    assert_not_null(User.find(auth_user._key).reset_token_digest)
  end

  test("a valid token sets a new password; the old one stops working") do
    token = auth_user.start_password_reset()
    assert_contains(res_body(get("/password/edit?token=#{token}")), "Nouveau mot de passe")
    response = post(
      "/password/update",
      {
        "token": token,
        "password": "another long passphrase",
        "password_confirmation": "another long passphrase"
      }
    )
    assert_eq(res_location(response), "/admin")
    stored = User.find(auth_user._key)
    assert(stored.authenticate("another long passphrase"))
    assert(!stored.authenticate("a long enough passphrase"))
  end

  test("refuses a short or mismatched password, and a bad token") do
    token = auth_user.start_password_reset()
    short = post(
      "/password/update",
      {
        "token": token,
        "password": "short",
        "password_confirmation": "short"
      }
    )
    assert_eq(res_status(short), 422)
    assert_contains(res_body(short), "au moins 12 caractères")
    mismatch = post(
      "/password/update",
      {
        "token": token,
        "password": "another long passphrase",
        "password_confirmation": "different long passphrase"
      }
    )
    assert_contains(res_body(mismatch), "diffèrent")
    assert_contains(res_body(get("/password/edit?token=nope")), "invalide ou expiré")
    assert_contains(res_body(post(
      "/password/update",
      {"token": "nope", "password": "x"}
    )), "invalide ou expiré")
    assert_contains(res_body(get("/password/edit")), "invalide ou expiré")
    assert(User.find(auth_user._key).authenticate("a long enough passphrase"))
  end
end

describe("E-mail confirmation") do
  before_each() do
    auth_reset()
  end

  test("a fresh link confirms the address once") do
    token = auth_user.start_email_confirmation()
    assert_contains(res_body(get("/confirm_email?token=#{token}")), "confirmée")
    assert(User.find(auth_user._key).confirmed?())
    assert_contains(res_body(get("/confirm_email?token=#{token}")), "invalide ou déjà utilisé")
  end

  test("resending says the same thing for every address") do
    assert_eq(res_status(get("/confirmation/resend")), 200)
    assert_contains(res_body(post("/confirmation/resend", {"email": "veille@vigie.example"})), "Si cette adresse")
    assert_contains(res_body(post("/confirmation/resend", {"email": "x@vigie.example"})), "Si cette adresse")
  end
end

describe("Sessions") do
  before_each() do
    auth_reset()
  end

  test("remember me sets a cookie, logout clears the session") do
    response = post(
      "/login",
      {
        "email": "veille@vigie.example",
        "password": "a long enough passphrase",
        "remember_me": "1"
      }
    )
    assert_eq(res_location(response), "/admin")
    assert_contains(res_header(response, "set-cookie").join(";"), "remember_token=")
    assert_not_null(User.find(auth_user._key).remember_token_digest)
    assert_eq(res_status(get("/admin")), 200)
    out = delete("/logout")
    assert_eq(res_location(out), "/login")
    assert_eq(res_location(get("/admin")), "/login")
  end

  test("a remember-me cookie alone opens a session") do
    token = auth_user.start_remember_me()
    set_request_cookie("remember_token", "#{auth_user._key}:#{token}")
    assert_eq(res_status(get("/admin")), 200)
  end

  test("a password reset closes the sessions opened before it") do
    post(
      "/login",
      {"email": "veille@vigie.example", "password": "a long enough passphrase"}
    )
    assert_eq(res_status(get("/admin")), 200)
    User.find(auth_user._key).finish_password_reset("a brand new passphrase")
    assert_eq(res_location(get("/admin")), "/login")
  end

  test("too many wrong passwords lock the account, the right one is then refused too") do
    (0 .. AUTH_MAX_FAILED_ATTEMPTS).each do |i|
      post(
        "/login",
        {"email": "veille@vigie.example", "password": "wrong #{i}"}
      )
    end
    assert(User.find(auth_user._key).locked?())
    locked = post(
      "/login",
      {"email": "veille@vigie.example", "password": "a long enough passphrase"}
    )
    assert_eq(res_status(locked), 401)
  end

  test("an unknown address costs the same answer") do
    response = post(
      "/login",
      {"email": "nobody@vigie.example", "password": "whatever passphrase"}
    )
    assert_eq(res_status(response), 401)
  end

  test("sign-up refuses a short password while sign-up is open") do
    User.all.each do |record|
      record.delete
    end
    response = post(
      "/signup",
      {"email": "first@vigie.example", "password": "short"}
    )
    assert_eq(res_status(response), 422)
    assert_eq(User.count, 0)
  end
end

describe("User model") do
  before_each() do
    auth_reset()
  end

  test("normalises the address and defaults the role") do
    stored = User.find(auth_user._key)
    assert_eq(stored.role, "member")
    assert(!stored.admin?())
    assert_null(stored.password_error("a long enough passphrase"))
    assert_contains(stored.password_error(""), "obligatoire")
  end

  test("forgets remember-me, and an expired lock opens again") do
    token = auth_user.start_remember_me()
    assert(auth_user.remembered_by?(token))
    auth_user.forget_me()
    assert(!auth_user.remembered_by?(token))
    assert(auth_user.forget_me())
    auth_user.locked_at = DateTime.utc.to_unix - AUTH_LOCKOUT_SECONDS - 10
    auth_user.failed_attempts = 99
    assert(!auth_user.locked?())
    assert(auth_user.reset_token_expired?())
    assert(auth_user.confirmation_token_expired?())
  end
end
