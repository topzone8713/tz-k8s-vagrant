#!/usr/bin/env bash

#https://yunhochung.medium.com/k8s-%EB%8C%80%EC%89%AC%EB%B3%B4%EB%93%9C-%EC%84%A4%EC%B9%98-%EB%B0%8F-%EC%99%B8%EB%B6%80-%EC%A0%91%EC%86%8D-%EA%B8%B0%EB%8A%A5-%EC%B6%94%EA%B0%80%ED%95%98%EA%B8%B0-22ed1cd0999f

source /root/.bashrc
cd /vagrant/tz-local/resource/metallb

shopt -s expand_aliases

NS=metallb-system
alias k="kubectl -n ${NS} --kubeconfig ~/.kube/config"

kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system

kubectl delete ns ${NS}
kubectl create ns ${NS}

#helm repo add metallb https://metallb.github.io/metallb
#helm repo update
#helm delete metallb -n ${NS}
#helm install metallb metallb/metallb -n ${NS}
#helm install metallb metallb/metallb -n ${NS} -f values.yaml

kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml -n ${NS}
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml -n ${NS}

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml -n ${NS}

#kubectl apply -f metallb.yaml -n ${NS}

# On first install only
k create secret generic -n ${NS} memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
k get pods -n ${NS}

k delete -f layer2-config.yaml -n ${NS}
k apply -f layer2-config.yaml -n ${NS}

k logs -l component=speaker -n ${NS}

k apply -f test.yaml -n ${NS}
k delete -f test.yaml -n ${NS}
exit 0