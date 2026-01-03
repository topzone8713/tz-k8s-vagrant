#!/usr/bin/env bash

source /root/.bashrc
function prop { key="${2}=" file="/root/.k8s/${1}" rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); rslt=$(echo "$rslt" | tr -d '\n' | tr -d '\r'); echo "$rslt"; }
#bash /vagrant/tz-local/resource/minio/install.sh
cd /vagrant/tz-local/resource/minio

#set -x
shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
basic_password=$(prop 'project' 'basic_password')
NS=devops

kubectl create namespace ${NS}
#k apply -f storageclass.yaml -n ${NS}

# MinIO 공식 Helm chart 사용 (개발 서버와 동일)
helm repo add minio https://charts.min.io/
helm repo update
helm uninstall minio -n ${NS} 2>/dev/null || true

# MinIO 공식 Helm chart 설치
cp -Rf values.yaml values.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" values.yaml_bak
sed -i "s/basic_password/${basic_password}/g" values.yaml_bak
helm upgrade --install minio minio/minio --version 5.4.0 -n ${NS} -f values.yaml_bak

sleep 60

MINIO_ROOT_USER=$(kubectl get secret --namespace ${NS} minio -o jsonpath="{.data.rootUser}" | base64 --decode; echo)
MINIO_ROOT_PASSWORD=$(kubectl get secret --namespace ${NS} minio -o jsonpath="{.data.rootPassword}" | base64 --decode; echo)
echo "MinIO Root User: ${MINIO_ROOT_USER}"
echo "MinIO Root Password: ${MINIO_ROOT_PASSWORD}"

# MinIO 외부 접속을 위한 Ingress 배포
cp -Rf minio-ingress.yaml minio-ingress.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" minio-ingress.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" minio-ingress.yaml_bak
kubectl apply -f minio-ingress.yaml_bak -n ${NS}

#kubectl -n ${NS} port-forward svc/minio 9000:9000
#kubectl -n ${NS} port-forward svc/minio-console 9001:9001

exit 0
