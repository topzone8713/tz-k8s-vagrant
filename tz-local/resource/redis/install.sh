#!/usr/bin/env bash

source /root/.bashrc
function prop { key="${2}=" file="/root/.k8s/${1}" rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); rslt=$(echo "$rslt" | tr -d '\n' | tr -d '\r'); echo "$rslt"; }
#bash /vagrant/tz-local/resource/redis/install.sh
cd /vagrant/tz-local/resource/redis

#set -x
shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

k8s_project=$(prop 'project' 'project')
NS=devops

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm uninstall redis-cluster-${k8s_project} -n ${NS}

helm upgrade --install redis-cluster-${k8s_project} bitnami/redis -n ${NS} -f values.yaml

sleep 60

# Redis 상태 확인
kubectl get pods -n ${NS} | grep redis-cluster-${k8s_project}

exit 0
