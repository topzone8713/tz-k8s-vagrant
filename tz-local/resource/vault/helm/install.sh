#!/usr/bin/env bash

source /root/.bashrc
#bash /vagrant/tz-local/resource/vault/helm/install.sh
cd /vagrant/tz-local/resource/vault/helm

#set -x
shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
vault_token=$(prop 'project' 'vault')
NS=vault

helm repo add hashicorp https://helm.releases.hashicorp.com
helm search repo hashicorp/vault
helm repo update

helm uninstall vault -n vault
k delete namespace vault
k create namespace vault

#kubectl -n vault delete secret generic eks-creds
#kubectl -n vault create secret generic eks-creds \
#    --from-literal=AWS_ACCESS_KEY_ID="${aws_access_key_id}" \
#    --from-literal=AWS_SECRET_ACCESS_KEY="${aws_secret_access_key}"

bash /vagrant/tz-local/resource/vault/vault-injection/cert.sh vault

cp -Rf values_cert.yaml values_cert.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" values_cert.yaml_bak
# --version 0.19.0
helm upgrade --debug --install --reuse-values vault hashicorp/vault -n vault -f values_cert.yaml_bak
kubectl taint nodes --all node-role.kubernetes.io/master-
#kubectl rollout restart statefulset.apps/vault -n vault

sleep 30
k get all -n vault

cp -Rf values_config.yaml values_config.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" values_config.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" values_config.yaml_bak
k apply -f values_config.yaml_bak -n vault

sleep 30
# to NodePort

#k patch svc vault-standby --type='json' -p '[{"op":"replace","path":"/spec/type","value":"NodePort"},{"op":"replace","path":"/spec/ports/0/nodePort","value":31700}]' -n vault
cp -Rf ingress-vault.yaml ingress-vault.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" ingress-vault.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" ingress-vault.yaml_bak
sed -i "s|NS|${NS}|g" ingress-vault.yaml_bak
k delete -f ingress-vault.yaml_bak -n vault
k apply -f ingress-vault.yaml_bak -n vault

#k port-forward vault-0 8200:8200 -n vault &
k get pods -l app.kubernetes.io/name=vault -n vault

sleep 60
# vault operator init
# vault operator init -key-shares=3 -key-threshold=2
#export VAULT_ADDR='http://127.0.0.1:8200'
#export VAULT_ADDR="http://vault.default.${k8s_project}.${k8s_domain}"
export VAULT_ADDR="https://vault.shoptools.co.kr"
echo $VAULT_ADDR

mkdir -p /vagrant/resources
k -n vault exec -ti vault-0 -- vault operator init -key-shares=3 -key-threshold=2 | sed 's/\x1b\[[0-9;]*m//g' > /vagrant/resources/unseal.txt
sleep 20
vault_token_new=$(cat /vagrant/resources/unseal.txt | grep "Initial Root Token:" | tail -n 1 | awk '{print $4}')
echo "#######################################################"
echo "vault_token_new: ${vault_token_new}"
echo "#######################################################"
if [[ "${vault_token_new}" != "" ]]; then
  touch /vagrant/resources/project
  awk '!/vault=/' /vagrant/resources/project > tmpfile && mv tmpfile /vagrant/resources/project
  echo "vault=${vault_token_new}" >> /vagrant/resources/project
  cp -Rf /vagrant/resources/project ~/.aws/project
  mkdir -p /home/vagrant/.aws
  cp -Rf /vagrant/resources/project /home/vagrant/.aws/project
fi

# vault operator unseal
#echo k -n vault exec -ti vault-0 -- vault operator unseal
#k -n vault exec -ti vault-0 -- vault operator unseal # ... Unseal Key 1
#k -n vault exec -ti vault-0 -- vault operator unseal # ... Unseal Key 2,3,4,5
#
#echo k -n vault exec -ti vault-1 -- vault operator unseal
#k -n vault exec -ti vault-1 -- vault operator unseal # ... Unseal Key 1
#k -n vault exec -ti vault-1 -- vault operator unseal # ... Unseal Key 2,3,4,5
#
#echo k -n vault exec -ti vault-2 -- vault operator unseal
#k -n vault exec -ti vault-2 -- vault operator unseal # ... Unseal Key 1
#k -n vault exec -ti vault-2 -- vault operator unseal # ... Unseal Key 2,3,4,5

cp -Rf values_config.yaml values_config.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" values_config.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" values_config.yaml_bak
k apply -f values_config.yaml_bak -n vault

sleep 30
# to NodePort

k -n vault get pods -l app.kubernetes.io/name=vault

#curl http://dooheehong323:31700/ui/vault/secrets

VAULT_VERSION="1.3.1"
curl -sO https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
unzip vault_${VAULT_VERSION}_linux_amd64.zip
rm -Rf vault_${VAULT_VERSION}_linux_amd64.zip
mv vault /usr/local/bin/
vault --version

#vault -autocomplete-install
#complete -C /usr/local/bin/vault vault
#vault -h

echo "
##[ Vault ]##########################################################
export VAULT_ADDR=http://vault.default.${k8s_project}.${k8s_domain}
vault login ${vault_token_new}

vault secrets list -detailed

vault kv list kv
vault kv put kv/my-secret my-value=yea
vault kv get kv/my-secret

vault kv put kv/tz-vault tz-value=yes
vault kv get kv/tz-vault

vault kv delete kv/tz-vault

vault kv metadata get kv/tz-vault
vault kv metadata delete kv/tz-vault


# aws key
vault secrets enable aws

vault write aws/config/root \
region=ap-southeast-1


#vault secrets enable -path=kv kv

# macos
brew tap hashicorp/tap
brew install hashicorp/tap/vault
export VAULT_ADDR=http://vault.default.${k8s_project}.${k8s_domain}
vault login xxxx
vault secrets list -detailed

vault audit enable file file_path=/home/vagrant/tmp/a.log

# path ex)
secrets
  apps
    app1_web
    app1_demon
  common
    api_key

# backup and restore
export CONSUL_HTTP_ADDR="consul.default.${k8s_project}.${k8s_domain}"
consul members

consul snapshot save backup.snap
vault operator raft snapshot save backup.snap
vault operator raft snapshot restore -force backup.snap

#######################################################################
" >> /vagrant/info
cat /vagrant/info

exit 0

