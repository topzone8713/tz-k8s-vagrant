#!/usr/bin/env bash

source /root/.bashrc
function prop { key="${2}=" file="/root/.k8s/${1}" rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); rslt=$(echo "$rslt" | tr -d '\n' | tr -d '\r'); echo "$rslt"; }
#bash /vagrant/tz-local/resource/postgresql/install.sh
cd /vagrant/tz-local/resource/postgresql

#set -x
shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

k8s_project=$(prop 'project' 'project')
basic_password=$(prop 'project' 'basic_password')
NS=devops-dev

#k apply -f storageclass.yaml -n ${NS}

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm uninstall devops-postgres -n ${NS}

#--reuse-values
cp values.yaml values.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" values.yaml_bak
sed -i "s/basic_password/${basic_password}/g" values.yaml_bak
helm upgrade --install devops-postgres bitnami/postgresql -n ${NS} -f values.yaml_bak

sleep 240

POSTGRES_PASSWORD=$(kubectl get secret --namespace ${NS} devops-postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode; echo)
echo $POSTGRES_PASSWORD

# PostgreSQL 외부 접속을 위한 NodePort Service 배포
kubectl apply -f postgres-dev.yaml -n ${NS}

#k patch svc devops-postgres-postgresql -n ${NS} -p '{"spec": {"type": "LoadBalancer", "loadBalancerSourceRanges": [ "10.20.0.0/16",  ]}}'
#kubectl -n ${NS} port-forward svc/devops-postgres-postgresql 5432:5432

exit 0

POSTGRES_HOST=$(kubectl get svc devops-postgres-postgresql -n ${NS} | tail -n 1 | awk '{print $4}')
echo ${POSTGRES_HOST}
POSTGRES_PORT=5432

sudo apt-get update && sudo apt-get install postgresql-client -y
PGPASSWORD=${POSTGRES_PASSWORD} psql -h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -U postgres -d postgres -c "CREATE DATABASE test_db;"
PGPASSWORD=${POSTGRES_PASSWORD} psql -h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -U postgres -d postgres -c "\l"
echo PGPASSWORD=${POSTGRES_PASSWORD} psql -h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -U postgres -d postgres -c "\l"

