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
kubectl delete certificate self-signed-cert-tls -n devops

kubectl apply -f self-signed.yaml
sleep 10
kubectl get secrets self-signed-cert-tls
kubectl get secret self-signed-cert-tls -o jsonpath='{.data.ca\.crt}' | base64 --decode > self-signed.crt

# 로컬 환경 테스트
#echo "192.168.86.200  test.topzone-k8s.topzone.me" | sudo tee -a /etc/hosts

rm -Rf csr_config.ext signing_config.ext

kubectl apply -f nginx2.yaml
kubectl apply -f nginx3.yaml

export NS=devops
export k8s_project=topzone-k8s
export k8s_domain=topzone-k8s.topzone.me

