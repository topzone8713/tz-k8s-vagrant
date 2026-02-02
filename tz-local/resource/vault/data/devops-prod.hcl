
path "secret/*" {
  capabilities = ["list"]
}
path "secret/data/devops-prod/*" {
  capabilities = ["create", "update", "read"]
}
path "secret/delete/devops-prod/*" {
  capabilities = ["delete", "update"]
}
path "secret/undelete/devops-prod/*" {
  capabilities = ["update"]
}
path "secret/destroy/devops-prod/*" {
  capabilities = ["update"]
}
path "secret/metadata/devops-prod/*" {
  capabilities = ["list", "read", "delete"]
}
path "secret/data/shared/*" {
  capabilities = ["read"]
}
