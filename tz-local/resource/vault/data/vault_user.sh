#!/usr/bin/env bash

#set -x

source /root/.bashrc
#bash /vagrant/tz-local/resource/vault/data/vault_user.sh
cd /vagrant/tz-local/resource/vault/data

k8s_project=hyper-k8s  #k8s_project=hyper-k8s  #$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
vault_token=$(prop 'project' 'vault')

#export VAULT_ADDR="http://vault.default.${k8s_project}.${k8s_domain}"
export VAULT_ADDR="https://vault.shoptools.co.kr"
echo ${VAULT_ADDR}
vault login ${vault_token}

vault secrets enable aws
vault secrets enable consul
vault auth enable kubernetes
vault secrets enable database
vault secrets enable pki
vault secrets enable -version=2 kv
vault secrets enable kv-v2
vault kv enable-versioning secret/
vault secrets enable -path=kv kv
vault secrets enable -path=secret/ kv
vault auth enable userpass

vault kv enable-versioning secret/

userpass_accessor="$(vault auth list | awk '/^userpass/ {print $3}')"
cp userpass.hcl userpass.hcl_bak
sed -i "s/userpass_accessor/${userpass_accessor}/g" userpass.hcl_bak
vault policy write tz-vault-userpass /vagrant/tz-local/resource/vault/data/userpass.hcl_bak

PROJECTS=(argocd consul default devops devops-dev monitoring vault)
for item in "${PROJECTS[@]}"; do
  if [[ "${item}" != "NAME" ]]; then
    kubectl create ns ${item}
  fi
done

PROJECTS=(argocd consul default devops devops-dev monitoring vault)
for item in "${PROJECTS[@]}"; do
  if [[ "${item}" != "NAME" ]]; then
    staging="dev"
    if [[ "${item/*-dev/}" == "" ]]; then
      project=${item/-prod/}
      staging="dev"
    else
      project=${item}-prod
      project_qa=${item}-qa
      staging="prod"
    fi
    echo "=====================staging: ${staging}"
    echo "/vagrant/tz-local/resource/vault/data/${project}.hcl"
    if [[ -f /vagrant/tz-local/resource/vault/data/${project}.hcl ]]; then
      echo ${item} : ${item/*-dev/}
      echo project: ${project}
      echo role: auth/kubernetes/role/${project}
      echo policy: tz-vault-${project}
      echo svcaccount: ${item}-svcaccount
      vault policy write tz-vault-${project} /vagrant/tz-local/resource/vault/data/${project}.hcl
      vault write auth/kubernetes/role/${project} \
              bound_service_account_names=argocd-repo-server,${project}-svcaccount \
              bound_service_account_namespaces=${item} \
              policies=tz-vault-${project} \
              ttl=24h
      if [ "${staging}" == "prod" ]; then
        echo project_qa: ${project_qa}
        echo role_qa: auth/kubernetes/role/${project_qa}
        echo project_qa: tz-vault-${project_qa}
        echo svcaccount_qa: ${project_qa}-svcaccount
        echo vault policy write tz-vault-${project_qa} /vagrant/tz-local/resource/vault/data/${project_qa}.hcl
        vault policy write tz-vault-${project_qa} /vagrant/tz-local/resource/vault/data/${project_qa}.hcl
        vault write auth/kubernetes/role/${project_qa} \
                bound_service_account_names=argocd-repo-server,${project_qa}-svcaccount \
                bound_service_account_namespaces=${item} \
                policies=tz-vault-${project_qa} \
                ttl=24h
      fi
    fi
  fi
done

# set a secret engine
vault secrets list
vault secrets list -detailed

exit 0
