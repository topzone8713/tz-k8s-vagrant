#!/usr/bin/env bash

source /root/.bashrc
function prop { key="${2}=" file="/root/.k8s/${1}" rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); rslt=$(echo "$rslt" | tr -d '\n' | tr -d '\r'); echo "$rslt"; }
cd /vagrant/tz-local/resource/ingress_nginx/self-signed

NS=$1
if [[ "${NS}" == "" ]]; then
  NS=default
fi
k8s_project=$2
if [[ "${k8s_project}" == "" ]]; then
  k8s_project=$(prop 'project' 'project')
fi
k8s_domain=$3
if [[ "${k8s_domain}" == "" ]]; then
  k8s_domain=$(prop 'project' 'domain')
fi

#set -x
shopt -s expand_aliases
alias k="kubectl -n ${NS} --kubeconfig ~/.kube/config"

kubectl delete -f self-signed.yaml
kubectl delete secret ca-secret
kubectl delete -f ca-cert.yaml
kubectl delete -f nginx2.yaml
kubectl delete -f nginx3.yaml

kubectl apply -f self-signed.yaml
sleep 10
kubectl get secrets self-signed-cert-tls
kubectl get secret self-signed-cert-tls -o jsonpath='{.data.ca\.crt}' | base64 --decode > self-signed.crt

# Step 1: CA 키 및 인증서 생성
openssl req -x509 -newkey rsa:4096 -keyout self-signed.key -out self-signed.crt -days 365 -nodes -subj "/CN=topzone.me"

# Step 2: Kubernetes Secret 생성
kubectl create secret tls ca-secret --cert=self-signed.crt --key=self-signed.key

# Step 3: CA Issuer 생성
kubectl apply -f ca-cert.yaml

# Step 5: 생성된 인증서 확인
kubectl get secrets ca-signed-cert-tls

# 로컬 환경 테스트
#echo "127.0.0.1 my.topzone.me" | sudo tee -a /etc/hosts

rm -Rf csr_config.ext signing_config.ext

kubectl apply -f nginx2.yaml
kubectl apply -f nginx3.yaml

export NS=devops
export k8s_project=topzone-k8s
export k8s_domain=topzone.me

cp -Rf nginx-ingress.yaml nginx-ingress.yaml_bak
sed -ie "s|NS|${NS}|g" nginx-ingress.yaml_bak
sed -ie "s/k8s_project/${k8s_project}/g" nginx-ingress.yaml_bak
sed -ie "s/k8s_domain/${k8s_domain}/g" nginx-ingress.yaml_bak
kubectl delete -f nginx-ingress.yaml_bak -n ${NS}
kubectl delete svc nginx -n ${NS}
kubectl apply -f nginx-ingress.yaml_bak -n ${NS}
echo curl "http://test.${NS}.${k8s_project}.${k8s_domain}"

kubectl delete -f nginx3.yaml
kubectl delete -f nginx3.yaml -n ${NS}
kubectl apply -f nginx3.yaml -n ${NS}

