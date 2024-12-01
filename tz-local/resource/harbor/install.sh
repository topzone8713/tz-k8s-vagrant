#!/usr/bin/env bash

#https://kubesphere.io/docs/devops-user-guide/how-to-integrate/harbor/

source /root/.bashrc
function prop { key="${2}=" file="/root/.aws/${1}" rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); echo "$rslt"; }
#bash /topzone/tz-local/resource/harbor/install.sh
cd /topzone/tz-local/resource/harbor

#set -x
shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
admin_password=$(prop 'project' 'admin_password')
basic_password=$(prop 'project' 'basic_password')
NS=default

helm repo add harbor https://helm.goharbor.io
helm uninstall harbor-release
#helm show values harbor/harbor > values.yaml
cp -Rf values.yaml values.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" values.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" values.yaml_bak
sed -i "s|NS|devops|g" values.yaml_bak
#--reuse-values
helm upgrade --debug --install --reuse-values harbor-release harbor/harbor -f values.yaml_bak

sleep 30

#cp -Rf harbor-ingress.yaml harbor-ingress.yaml_bak
#sed -i "s/k8s_project/${k8s_project}/g" harbor-ingress.yaml_bak
#sed -i "s/k8s_domain/${k8s_domain}/g" harbor-ingress.yaml_bak
#sed -i "s|NS|devops|g" harbor-ingress.yaml_bak
#k delete -f harbor-ingress.yaml_bak
#k apply -f harbor-ingress.yaml_bak

echo https://harbor.devops.${k8s_project}.${k8s_domain}
echo admin / Harbor12345

#new project: ks-devops-harbor
#NEW ROBOT ACCOUNT in Robot Accounts.
#robot account: robot-test

#      tolerations: []
#    enabled: false
#  local_registry: '172.20.247.60:80'  # Add a new field of Harbor address to this line.
#  logging:
#    enabled: false

#vi /etc/docker/daemon.json
#{
#  "insecure-registries":["harbor.devops.topzone-k8s.topzone.me"]
#}
#systemctl restart docker
#
#docker login harbor.devops.topzone-k8s.topzone.me
#admin / ${admin_password}

