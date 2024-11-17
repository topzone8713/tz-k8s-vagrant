#!/usr/bin/env bash

source /root/.bashrc
cd /vagrant/tz-local/resource/docker-repo

#set -x
shopt -s expand_aliases
alias k='kubectl'

k8s_project=hyper-k8s  #$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
dockerhub_id=$(prop 'project' 'dockerhub_id')
dockerhub_password=$(prop 'project' 'dockerhub_password')

apt-get update -y
apt-get -y install docker.io jq
usermod -G docker ubuntu
chown -Rf vagrant:vagrant /var/run/docker.sock

mkdir -p ~/.docker
docker login -u="${dockerhub_id}" -p="${dockerhub_password}"

sleep 2

cat ~/.docker/config.json
#mkdir -p /root/.docker
#cp -Rf ~/.docker/config.json /root/.docker/config.json
#chown -Rf vagrant:vagrant /root/.docker

kubectl delete secret tz-registrykey
kubectl create secret generic tz-registrykey \
    --from-file=.dockerconfigjson=/root/.docker/config.json \
    --type=kubernetes.io/dockerconfigjson

kubectl create ns argocd
kubectl create ns consul
kubectl create ns default
kubectl create ns devops
kubectl create ns devops-dev
kubectl create ns monitoring
kubectl create ns vault

PROJECTS=(argocd consul default devops devops-dev monitoring vault)
for item in "${PROJECTS[@]}"; do
  if [[ "${item}" != "NAME" ]]; then
    echo "===================== ${item}"
    kubectl delete secret tz-registrykey -n ${item}
    kubectl create secret generic tz-registrykey \
      -n ${item} \
      --from-file=.dockerconfigjson=/root/.docker/config.json \
      --type=kubernetes.io/dockerconfigjson
  fi
done

#echo "
#apiVersion: v1
#kind: Secret
#metadata:
#  name: tz-registrykey
#data:
#  .dockerconfigjson: docker-config
#type: kubernetes.io/dockerconfigjson
#" > docker-config.yaml
#
#DOCKER_CONFIG=$(cat /root/.docker/config.json | base64 | tr -d '\r')
#DOCKER_CONFIG=$(echo $DOCKER_CONFIG | sed 's/ //g')
#echo "${DOCKER_CONFIG}"
#cp docker-config.yaml docker-config.yaml_bak
#sed -i "s/DOCKER_CONFIG/${DOCKER_CONFIG}/g" docker-config.yaml_bak
#k apply -f docker-config.yaml_bak

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
