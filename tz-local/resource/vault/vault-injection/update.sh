#!/usr/bin/env bash

source /root/.bashrc
#bash /vagrant/tz-local/resource/vault/vault-injection/update.sh
cd /vagrant/tz-local/resource/vault/vault-injection

k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
VAULT_TOKEN=$(prop 'project' 'vault')
AWS_REGION=$(prop 'config' 'region')

#export VAULT_ADDR="http://vault.default.${k8s_project}.${k8s_domain}"
export VAULT_ADDR="https://vault.shoptools.co.kr"
vault login ${VAULT_TOKEN}

vault list auth/kubernetes/role

#bash /vagrant/tz-local/resource/vault/vault-injection/cert.sh default
kubectl get csr -o name | xargs kubectl certificate approve

PROJECTS=(argocd consul default devops devops-dev monitoring vault)
for item in "${PROJECTS[@]}"; do
  echo "====================="
  echo ${item}
  accounts="default"
  namespaces="default"
  staging="dev"
  if [[ "${item/*-dev/}" == "" ]]; then
    project=${item/-prod/}
    accounts=${accounts},${item}-svcaccount
    namespaces=${namespaces},${item}  # devops-dev
    echo "===================dev==${project} / ${namespaces}"
  else
    project=${item}-prod
    project_qa=${item}-qa
    accounts=${accounts},${item}-dev-svcaccount,${item}-qa-svcaccount,${project}-svcaccount # devops-dev devops-prod
    namespaces=${namespaces},${item/-prod/}-dev,${item/-prod/}  # devops-dev devops
    staging="prod"
  fi
  echo "===================${staging}==${project} / ${namespaces}"
#  for value in "${accounts[@]}"; do
#     echo $value
#  done
#  for value in "${namespaces[@]}"; do
#     echo $value
#  done
  if [[ -f /vagrant/tz-local/resource/vault/data/${project}.hcl ]]; then
    echo ${item} : ${item/*-dev/}
    echo project: ${project}
    vault write auth/kubernetes/role/${project} \
            bound_service_account_names=${accounts} \
            bound_service_account_namespaces=${namespaces} \
            policies=tz-vault-${project} \
            ttl=24h
    vault policy write tz-vault-${project} /vagrant/tz-local/resource/vault/data/${project}.hcl
    vault kv put secret/${project}/dbinfo name='localhost' passwod=1111 ttl='30s'
    vault kv put secret/${project}/foo name='localhost' passwod=1111 ttl='30s'
    vault read auth/kubernetes/role/${project}
    if [ "${staging}" == "prod" ]; then
      vault write auth/kubernetes/role/${project_qa} \
              bound_service_account_names=${accounts} \
              bound_service_account_namespaces=${namespaces} \
              policies=tz-vault-${project_qa} \
              ttl=24h
      vault policy write tz-vault-${project_qa} /vagrant/tz-local/resource/vault/data/${project_qa}.hcl
      vault kv put secret/${project_qa}/dbinfo name='localhost' passwod=1111 ttl='30s'
      vault kv put secret/${project_qa}/foo name='localhost' passwod=1111 ttl='30s'
      vault read auth/kubernetes/role/${project_qa}
    fi
  fi
done

exit 0
