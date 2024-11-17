#!/usr/bin/env bash

source /root/.bashrc
cd /vagrant/tz-local/resource/monitoring/rules
#bash /vagrant/tz-local/resource/monitoring/rules/update.sh

#set -x
shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

eks_project=$(prop 'project' 'project')
eks_domain=$(prop 'project' 'domain')
admin_password=$(prop 'project' 'admin_password')
basic_password=$(prop 'project' 'basic_password')
STACK_VERSION=44.3.0
NS=monitoring

cp -Rf rule-values.yaml rule-values.yaml_bak
sed -i "s/eks_project/${eks_project}/g" rule-values.yaml_bak
sed -i "s/eks_domain/${eks_domain}/g" rule-values.yaml_bak

helm upgrade --debug --reuse-values --install prometheus prometheus-community/kube-prometheus-stack \
    -n ${NS} \
    --version ${STACK_VERSION} \
    -f rule-values.yaml
