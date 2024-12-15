#!/usr/bin/env bash

source /root/.bashrc
function prop { key="${2}=" file="/root/.k8s/${1}" rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); rslt=$(echo "$rslt" | tr -d '\n' | tr -d '\r'); echo "$rslt"; }
#bash /vagrant/tz-local/resource/mysql/install.sh
cd /vagrant/tz-local/resource/mysql

#set -x
shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

k8s_project=$(prop 'project' 'project')
NS=devops-dev

#k apply -f storageclass.yaml -n ${NS}

helm repo add stable https://charts.helm.sh/stable
helm repo update
helm uninstall devops-mysql -n ${NS}

pushd `pwd`
cd /vagrant/terraform-aws-eks/workspace/base
allowed_management_cidr_blocks=$(terraform output allowed_management_cidr_blocks)
allowed_management_cidr_blocks=`echo ${allowed_management_cidr_blocks} | sed "s|, ]| ]|g" | tr "\n" " "`
popd
echo ${allowed_management_cidr_blocks}
cp values.yaml values.yaml_bak
export allowed_management_cidr_blocks=${allowed_management_cidr_blocks}
envsubst < "values.yaml" > "values.yaml_bak"

#--reuse-values
helm upgrade --install devops-mysql stable/mysql -n ${NS} -f values.yaml
#k patch svc devops-mysql -n ${NS} -p '{"spec": {"type": "LoadBalancer", "loadBalancerSourceRanges": [ "10.20.0.0/16",  ]}}'

sleep 240

MYSQL_ROOT_PASSWORD=$(kubectl get secret --namespace ${NS} devops-mysql -o jsonpath="{.data.mysql-root-password}" | base64 --decode; echo)
echo $MYSQL_ROOT_PASSWORD

#k patch svc devops-mysql -n ${NS} -p '{"spec": {"type": "LoadBalancer"}}'
#kubectl -n ${NS} port-forward svc/mysql 3306

MYSQL_HOST=$(kubectl get svc devops-mysql -n ${NS} | tail -n 1 | awk '{print $4}')
echo ${MYSQL_HOST}
MYSQL_PORT=3306
MYSQL_ROOT_PASSWORD=oIjrdhfHaT

sudo apt-get update && sudo apt-get install mysql-client -y
mysql -h ${MYSQL_HOST} -P ${MYSQL_PORT} --user=root -p${MYSQL_ROOT_PASSWORD} -e "CREATE database test_db;"
mysql -h ${MYSQL_HOST} -P ${MYSQL_PORT} --user=root -p${MYSQL_ROOT_PASSWORD} -e "SHOW databases;"
echo mysql -h ${MYSQL_HOST} -P ${MYSQL_PORT} --user=root -p${MYSQL_ROOT_PASSWORD} -e "SHOW databases;"
#mysql_config_editor print --all

exit 0

ELB_NM=$(echo $MYSQL_HOST | cut -d "." -f 1 | cut -d "-" -f 1)
echo ${ELB_NM}
SQG=$(aws elb describe-load-balancers --load-balancer-name ${ELB_NM} | grep SecurityGroups -A 1 | tail -n 1 | awk -F\" '{print $2}')
echo ${SQG}
aws ec2 authorize-security-group-ingress --group-id ${SQG} --protocol tcp --port 22 --cidr 43.224.104.241/32
aws ec2 describe-security-groups --group-id ${SQG}

