#!/usr/bin/env bash

source /root/.bashrc
# bash /vagrant/tz-local/resource/argocd/install.sh
cd /vagrant/tz-local/resource/argocd

#set -x
shopt -s expand_aliases

k8s_project=hyper-k8s  #$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
admin_password=$(prop 'project' 'admin_password')
github_token=$(prop 'project' 'github_token')
basic_password=$(prop 'project' 'basic_password')

alias k='kubectl --kubeconfig ~/.kube/config'

k delete namespace argocd
k create namespace argocd
k delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
k apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
sleep 20
k patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
sleep 120
TMP_PASSWORD=$(k -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "############################################"
echo "TMP_PASSWORD: ${TMP_PASSWORD}"
echo "############################################"

VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
sudo chmod +x /usr/local/bin/argocd
#brew tap argoproj/tap
#brew install argoproj/tap/argocd
#argocd

ARGOCD_SERVER=`k get ing -n argocd | grep -w "ingress-argocd " | awk '{print $3}'`
argocd login ${ARGOCD_SERVER} --username admin --password ${TMP_PASSWORD} --insecure
argocd account update-password --account admin --current-password ${TMP_PASSWORD} --new-password ${admin_password}

# basic auth
#https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/
#https://kubernetes.github.io/ingress-nginx/examples/auth/basic/
#echo ${basic_password} | htpasswd -i -n admin > auth
#k create secret generic basic-auth-argocd --from-file=auth -n argocd
#k get secret basic-auth-argocd -o yaml -n argocd
#rm -Rf auth

cp -Rf ingress-argocd.yaml ingress-argocd.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" ingress-argocd.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" ingress-argocd.yaml_bak
sed -i "s/AWS_REGION/${AWS_REGION}/g" ingress-argocd.yaml_bak
k delete -f ingress-argocd.yaml_bak -n argocd
k apply -f ingress-argocd.yaml_bak -n argocd

#k patch deploy/argocd-server -p '{"spec": {"template": {"spec": {"nodeSelector": {"team": "devops", "environment": "prod"}}}}}' -n argocd
#k patch deploy/argocd-applicationset-controller -p '{"spec": {"template": {"spec": {"nodeSelector": {"team": "devops", "environment": "prod"}}}}}' -n argocd
#k patch deploy/argocd-redis -p '{"spec": {"template": {"spec": {"nodeSelector": {"team": "devops", "environment": "prod"}}}}}' -n argocd
#k patch deploy/argocd-notifications-controller -p '{"spec": {"template": {"spec": {"nodeSelector": {"team": "devops", "environment": "prod"}}}}}' -n argocd
#k patch deploy/argocd-repo-server -p '{"spec": {"template": {"spec": {"nodeSelector": {"team": "devops", "environment": "prod"}}}}}' -n argocd
#k patch deploy/argocd-dex-server -p '{"spec": {"template": {"spec": {"nodeSelector": {"team": "devops", "environment": "prod"}}}}}' -n argocd

k patch deploy/argocd-redis -p '{"spec": {"template": {"spec": {"imagePullSecrets": [{"name": "tz-registrykey"}]}}}}' -n argocd

argocd login ${ARGOCD_SERVER} --username admin --password ${admin_password} --insecure
argocd repo add https://github.com/doohee323/tz-argocd-repo \
  --username doohee323 --password ${github_token}

bash /vagrant/tz-local/resource/argocd/update.sh
bash /vagrant/tz-local/resource/argocd/update.sh

exit 0
