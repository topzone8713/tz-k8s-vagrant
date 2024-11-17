#!/usr/bin/env bash

# alert
#https://github.com/grafana/oncall/tree/main/helm/oncall

source /root/.bashrc
#bash /vagrant/tz-local/resource/monitoring/oncall/install.sh
cd /vagrant/tz-local/resource/monitoring/oncall

#set -x
shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

eks_project=$(prop 'project' 'project')
eks_domain=$(prop 'project' 'domain')
admin_password=$(prop 'project' 'admin_password')
basic_password=$(prop 'project' 'basic_password')
STACK_VERSION=16.6.0

NS=monitoring

helm repo add oncall https://github.com/grafana/oncall/tree/dev/helm/oncall
helm repo update

helm install \
    --wait \
    release-oncall \
    -n ${NS} -f values.yaml_bak \
    .

helm upgrade \
    --install \
    --wait \
    release-oncall \
    -n ${NS} -f values.yaml_bak \
    .
