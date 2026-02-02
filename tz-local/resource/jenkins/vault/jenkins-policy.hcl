
path "secret/*" {
  capabilities = ["list"]
}
path "secret/data/shared/*" {
  capabilities = ["read"]
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


