#!/usr/bin/env bash

source /root/.bashrc
function prop { key="${2}=" file="/root/.k8s/${1}" rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); rslt=$(echo "$rslt" | tr -d '\n' | tr -d '\r'); echo "$rslt"; }
cd /vagrant/tz-local/resource/docker-repo

#set -x
shopt -s expand_aliases
alias k='kubectl'

k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
dockerhub_id=$(prop 'project' 'dockerhub_id')
dockerhub_password=$(prop 'project' 'dockerhub_password')
docker_url=$(prop 'project' 'docker_url')

#kubectl describe cm/coredns -n kube-system > coredns.yqml
#kubectl edit cm/coredns -n kube-system
#
#data:
#  Corefile: |
#    .:53 {
#        errors {
#        }
#        health {
#            lameduck 5s
#        }
#        ready
#        ~~~~
#    }
#    harbor.harbor.topzone-k8s.topzone.me:53 {
#        hosts {
#            192.168.86.200    harbor.harbor.topzone-k8s.topzone.me
#        }
#    }

#kubectl -n kube-system rollout restart deployment coredns

# apt-get update && apt-get install dnsutils -y
# nslookup harbor.harbor.topzone-k8s.topzone.me

apt-get update -y
apt-get -y install docker.io jq
usermod -G docker ubuntu
chown -Rf ubuntu:ubuntu /var/run/docker.sock

mkdir -p ~/.docker
docker login -u="${dockerhub_id}" -p="${dockerhub_password}"
echo "Harbor12345" | docker login harbor.harbor.topzone-k8s.topzone.me -u admin --password-stdin

sleep 2

cat ~/.docker/config.json

kubectl delete secret tz-registrykey
kubectl create secret generic tz-registrykey \
    --from-file=.dockerconfigjson=/root/.docker/config.json \
    --type=kubernetes.io/dockerconfigjson

#PROJECTS=(default)
PROJECTS=(argocd consul jenkins default devops devops-dev monitoring vault)
for item in "${PROJECTS[@]}"; do
  if [[ "${item}" != "NAME" ]]; then
    echo "===================== ${item}"
    kubectl create namespace ${item}
    kubectl delete secret tz-registrykey -n ${item}
    kubectl create secret generic tz-registrykey \
      -n ${item} \
      --from-file=.dockerconfigjson=/root/.docker/config.json \
      --type=kubernetes.io/dockerconfigjson
  fi
done

kubectl get secret tz-registrykey --output=yaml
kubectl get secret tz-registrykey -n vault --output=yaml

kubectl get secret tz-registrykey --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode

exit 0

spec:
  containers:
  - name: private-reg-container
    image: <your-private-image>
  imagePullSecrets:
    - name: tz-registrykey

docker login index.docker.io
docker pull index.docker.io/devops-utils2:latest
