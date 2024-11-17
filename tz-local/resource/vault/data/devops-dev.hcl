
path "secret/*" {
  capabilities = ["list"]
}
path "secret/data/devops-dev/*" {
  capabilities = ["create", "update", "read"]
}
path "secret/delete/devops-dev/*" {
  capabilities = ["delete", "update"]
}
path "secret/undelete/devops-dev/*" {
  capabilities = ["update"]
}
path "secret/destroy/devops-dev/*" {
  capabilities = ["update"]
}
path "secret/metadata/devops-dev/*" {
  capabilities = ["list", "read", "delete"]
}
path "secret/data/shared/*" {
  capabilities = ["read"]
}
