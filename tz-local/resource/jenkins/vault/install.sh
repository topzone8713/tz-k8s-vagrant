#!/usr/bin/env bash

cd /topzone/tz-local/resource/jenkins/vault

k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
vault_token=$(prop 'project' 'vault')

#set -x
vault -autocomplete-install
complete -C /usr/local/bin/vault vault
#vault -h

export VAULT_ADDR=http://vault.default.${k8s_project}.${k8s_domain}
vault login ${vault_token}

vault auth enable approle
vault secrets enable kv-v2
vault kv enable-versioning secret/

vault policy write jenkins jenkins-policy.hcl
vault policy list

vault write auth/approle/role/jenkins \
     secret_id_ttl=0 \
     token_num_uses=0 \
     token_ttl=0 \
     token_max_ttl=0 \
     secret_id_num_uses=0 \
     policies="jenkins"

# Get RoleID and SecretID
role_id=$(vault read auth/approle/role/jenkins/role-id)
role_id=$(echo $role_id | awk '{print $6}')
awk '!/jenkins_vault_role_id=/' /topzone/resources/project > tmpfile && mv tmpfile /topzone/resources/project
echo "jenkins_vault_role_id=${role_id}" >> /topzone/resources/project

secret_id=$(vault write -f auth/approle/role/jenkins/secret-id)
secret_id=$(echo $secret_id | awk '{print $6}')
#Key                   Value
#---                   -----
#secret_id             4b59eaa2-xxx
awk '!/jenkins_vault_secret_id=/' /topzone/resources/project > tmpfile && mv tmpfile /topzone/resources/project
echo "jenkins_vault_secret_id=${secret_id}" >> /topzone/resources/project

cp -Rf /topzone/resources/project /root/.aws/project

# Create dbinfo secret with 3 keys to read in jenkins pipeline
tee dbinfo.json <<"EOF"
{
  "name": "localhost",
  "passwod": "1111",
  "ttl": "30s"
}
EOF
vault kv put secret/devops-dev/dbinfo @dbinfo.json
vault kv delete secret/devops-dev/dbinfo
vault kv get secret/devops-dev/dbinfo

exit 0
