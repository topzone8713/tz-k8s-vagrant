
path "auth/userpass/users/{{identity.entity.aliases.userpass_accessor.name}}" {
  capabilities = [ "update" ]
  allowed_parameters = {
    "password" = []
  }
}
