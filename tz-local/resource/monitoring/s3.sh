#!/usr/bin/env bash

# https://rtfm.co.ua/en/grafana-loki-architecture-and-running-in-kubernetes-with-aws-s3-storage-and-boltdb-shipper/
# https://medium.com/techlogs/grafana-loki-with-aws-s3-backend-through-irsa-in-aws-kubernetes-cluster-93577dc482a
# https://grafana.com/docs/loki/latest/configuration/examples/#3-s3-without-credentials-snippetyaml

source /root/.bashrc
function prop { key="${2}=" file="/root/.k8s/${1}" rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); echo "$rslt"; }
#bash /topzone/tz-local/resource/monitoring/s3.sh
cd /topzone/tz-local/resource/monitoring

#set -x
shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
admin_password=$(prop 'project' 'admin_password')
basic_password=$(prop 'project' 'basic_password')
grafana_goauth2_client_id=$(prop 'project' 'grafana_goauth2_client_id')
grafana_goauth2_client_secret=$(prop 'project' 'grafana_goauth2_client_secret')
aws_access_key_id=$(prop 'credentials' 'aws_access_key_id')
AWS_REGION=$(prop 'config' 'region')
aws_secret_access_key=$(prop 'credentials' 'aws_secret_access_key')
smtp_password=$(prop 'project' 'smtp_password')
STACK_VERSION=44.3.0
NS=monitoring

cp -Rf s3_loki.yaml s3_loki.yaml_bak
sed -i "s/AWS_REGION/${AWS_REGION}/g" s3_loki.yaml_bak
sed -i "s/aws_access_key_id/${aws_access_key_id}/g" s3_loki.yaml_bak
sed -i "s/aws_secret_access_key/${aws_secret_access_key}/g" s3_loki.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" s3_loki.yaml_bak

s3_loki=$(cat s3_loki.yaml_bak | base64 -w0)
cp s3_loki-secret.yaml s3_loki-secret.yaml_bak
sed -i "s|LOKI_ENCODE|${s3_loki}|g" s3_loki-secret.yaml_bak
kubectl -n ${NS} apply -f s3_loki-secret.yaml_bak
kubectl rollout restart statefulset.apps/loki -n ${NS}

# retention
# https://grafana.com/docs/loki/latest/operations/storage/retention/