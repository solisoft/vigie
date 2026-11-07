# Admin gate: a signed-in user, or a redirect to the sign-in page.
# (`load_current_user`, order 5, has already filled req["current_user"].)

# order: 20
# scope_only: true

def require_login(req)
  return redirect("/login") if req["current_user"].nil?

  req
end
