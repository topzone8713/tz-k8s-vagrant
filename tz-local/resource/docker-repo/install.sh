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

#kubectl -n kube-system edit configmap coredns

#apiVersion: v1
#kind: ConfigMap
#metadata:
#  name: coredns
#  namespace: kube-system
#data:
#  Corefile: |
#    .:53 {
#    errors {
#    }
#    health {
#        lameduck 5s
#    }
#    hosts {
#        192.168.86.200 harbor.harbor.topzone-k8s.topzone.me
#        fallthrough
#    }
#    ready

kubectl -n kube-system rollout restart deployment coredns


mkdir -p /root/.docker
cp -Rf /vagrant/resources/config.json /root/.docker/config.json
chown -Rf topzone:topzone /root/.docker

kubectl delete secret tz-registrykey -n kube-system
kubectl create secret generic tz-registrykey \
    --from-file=.dockerconfigjson=config.json \
    --type=kubernetes.io/dockerconfigjson -n kube-system

#  --docker-server=https://nexus.topzone-k8s.topzone.me:5000/v2/ \
#kubectl get secret tz-registrykey --output=yaml

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
DOCKER_CONFIG=$(cat /root/.docker/config.json | base64 | tr -d '\r')
DOCKER_CONFIG=$(echo $DOCKER_CONFIG | sed 's/ //g')
echo "${DOCKER_CONFIG}"
cp docker-config.yaml docker-config.yaml_bak
sed -i "s/DOCKER_CONFIG/${DOCKER_CONFIG}/g" docker-config.yaml_bak
kubectl apply -f docker-config.yaml_bak

#kubectl delete -f clusterPullSecret.yaml
#kubectl apply -f clusterPullSecret.yaml

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

kubectl delete secret docker-config -n jenkins
kubectl create secret generic docker-config \
     -n jenkins \
    --from-file=config.json=/root/.docker/config.json

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
