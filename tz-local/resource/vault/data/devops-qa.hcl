
path "secret/*" {
  capabilities = ["list"]
}
path "secret/data/devops-qa/*" {
  capabilities = ["create", "update", "read"]
}
path "secret/delete/devops-qa/*" {
  capabilities = ["delete", "update"]
}
path "secret/undelete/devops-qa/*" {
  capabilities = ["update"]
}
path "secret/destroy/devops-qa/*" {
  capabilities = ["update"]
}
path "secret/metadata/devops-qa/*" {
  capabilities = ["list", "read", "delete"]
}
path "secret/data/shared/*" {
  capabilities = ["read"]
}
