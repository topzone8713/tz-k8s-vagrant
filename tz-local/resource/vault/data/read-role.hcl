path "auth/*" {
  capabilities = ["list", "read"]
}
path "sys/*" {
  capabilities = ["list", "read"]
}
path "sys/policy" {
  capabilities = ["list", "read"]
}
path "sys/policy/acl/tz-vault-datateam-dev" {
  capabilities = ["create", "read", "update", "delete", "sudo", "list"]
}
path "auth/kubernetes/role" {
  capabilities = ["list", "read"]
}
