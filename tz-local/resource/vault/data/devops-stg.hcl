
path "secret/*" {
  capabilities = ["list"]
}
path "secret/data/devops-stg/*" {
  capabilities = ["create", "update", "read"]
}
path "secret/delete/devops-stg/*" {
  capabilities = ["delete", "update"]
}
path "secret/undelete/devops-stg/*" {
  capabilities = ["update"]
}
path "secret/destroy/devops-stg/*" {
  capabilities = ["update"]
}
path "secret/metadata/devops-stg/*" {
  capabilities = ["list", "read", "delete"]
}
path "secret/data/shared/*" {
  capabilities = ["read"]
}
