#!/usr/bin/env bash

source /root/.bashrc
#bash /vagrant/tz-local/resource/vault/external-secrets/install.sh
cd /vagrant/tz-local/resource/vault/external-secrets

k8s_domain=$(prop 'project' 'domain')
k8s_project=hyper-k8s  #$(prop 'project' 'project')
vault_token=$(prop 'project' 'vault')
NS=external-secrets

helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm uninstall external-secrets -n ${NS}
#--reuse-values
helm upgrade --debug --install external-secrets \
   external-secrets/external-secrets \
    -n ${NS} \
    --create-namespace \
    --set installCRDs=true

#export VAULT_ADDR=http://vault.default.${k8s_project}.${k8s_domain}
export VAULT_ADDR=https://vault.shoptools.co.kr
vault login ${vault_token}
#vault kv get secret/devops-prod/dbinfo
vault_tokend=`echo -n ${vault_token} | openssl base64 -A`

#PROJECTS=(default argocd devops-dev)
PROJECTS=(devops devops-dev)
for item in "${PROJECTS[@]}"; do
  if [[ "${item}" != "NAME" ]]; then
    STAGING="dev"
    if [[ "${item/*-dev/}" == "" ]]; then
      project=${item/-prod/}
      STAGING="dev"
      namespace=${project}
    else
      project=${item}-prod
      project_qa=${item}-qa
      STAGING="prod"
      namespace=${item}
    fi
    echo "=====================STAGING: ${STAGING}"
echo '
apiVersion: v1
kind: ServiceAccount
metadata:
  name: PROJECT-svcaccount
  namespace: "NAMESPACE"
---

apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: "PROJECT"
  namespace: "NAMESPACE"
spec:
  provider:
    vault:
      server: "https://vault.shoptools.co.kr"
      path: "secret"
      version: "v2"
      auth:
        tokenSecretRef:
          name: "vault-token"
          key: "token"

---
apiVersion: v1
kind: Secret
metadata:
  name: vault-token
  namespace: "NAMESPACE"
data:
  token: VAULT_TOKEN

' > secret.yaml

    cp secret.yaml secret.yaml_bak
    sed -i "s|PROJECT|${project}|g" secret.yaml_bak
    sed -i "s|NAMESPACE|${namespace}|g" secret.yaml_bak
    sed -i "s|VAULT_TOKEN|${vault_tokend}|g" secret.yaml_bak
    sed -i "s|k8s_project|${k8s_project}|g" secret.yaml_bak
    sed -i "s|k8s_domain|${k8s_domain}|g" secret.yaml_bak

    kubectl apply -f secret.yaml_bak

    if [ "${STAGING}" == "prod" ]; then
      cp secret.yaml secret.yaml_bak
      sed -i "s|PROJECT|${project_qa}|g" secret.yaml_bak
      sed -i "s|NAMESPACE|${namespace}|g" secret.yaml_bak
      sed -i "s|VAULT_TOKEN|${vault_tokend}|g" secret.yaml_bak
      sed -i "s|k8s_project|${k8s_project}|g" secret.yaml_bak
      sed -i "s|k8s_domain|${k8s_domain}|g" secret.yaml_bak
      kubectl apply -f secret.yaml_bak
    fi
  fi
done

rm -Rf secret.yaml secret.yaml_bak

kubectl apply -f test.yaml
kubectl -n devops describe externalsecret devops-externalsecret
kubectl get SecretStores,ClusterSecretStores,ExternalSecrets --all-namespaces

exit 0

NAMESPACE=devops
STAGING=prod

PROJECTS=(kubeconfig_k8s-main-p kubeconfig_k8s-main-t kubeconfig_k8s-main-s kubeconfig_k8s-main-u kubeconfig_k8s-main-c devops.pub devops.pem devops credentials config auth.env ssh_config)
for item in "${PROJECTS[@]}"; do
  if [[ "${item}" != "NAME" ]]; then
    bash vault.sh fput ${NAMESPACE}-${STAGING} ${item} ${item}
    #bash vault.sh fget ${NAMESPACE}-${STAGING} ${item} > ${item}
  fi
done
