#!/usr/bin/env bash

#set -x

## https://medium.com/@HoussemDellai/rbac-with-kubernetes-in-minikube-4deed658ea7b

PROJECTS=(devops-dev)
#PROJECTS=(devops devops-dev default argocd consul monitoring vault)
for item in "${PROJECTS[@]}"; do
  if [[ "${item}" != "NAME" ]]; then
    kubectl create ns ${item}

    staging="dev"
    if [[ "${item/*-dev/}" != "" ]]; then
      staging="prod"
    fi
cat <<EOF > sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${item}-svcaccount
  namespace: ${item}
EOF
    kubectl -n ${item} apply -f sa.yaml

    if [ "${staging}" == "prod" ]; then
cat <<EOF > sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${item}-stg-svcaccount
  namespace: ${item}
EOF
      kubectl -n ${item} apply -f sa.yaml
    fi
  fi
done
rm -Rf sa.yaml

echo "1. Create a client certificate"
mkdir cert && cd cert
# Generate a key 
openssl genrsa -out user1.key 2048
# CSR
openssl req -new -key user1.key -out user1.csr -subj "/CN=user1/O=group1"
# CRT (certificate)
openssl x509 -req -in user1.csr -CA ~/.minikube/ca.crt -CAkey ~/.minikube/ca.key -CAcreateserial -out user1.crt -days 500

echo "2. Create a user"
# Set a user entry in kubeconfig
# ** under cert folder
kubectl config set-credentials user1 --client-certificate=user1.crt --client-key=user1.key
# Set a context entry in kubeconfig
kubectl config get-contexts
kubectl config set-context user1-context --cluster=minikube --user=user1
# kubectl config view

# 2.3. Switching to the created user
kubectl config use-context user1-context
kubectl config current-context # check the current context
#kubectl create namespace ns-test # Error from server (Forbidden): namespaces is forbidden: User "user1" cannot create resource "namespaces" in API group "" at the cluster scope

echo "3. Grant access to the user"
# Create a Role and BindingRole
kubectl config use-context minikube
kubectl apply -f makeuser/user1.yaml
kubectl get roles
kubectl get rolebindings

kubectl config use-context user1-context
kubectl create namespace ns-test # won't succeed, Forbidden
kubectl get pods # this will succeed !

rm -Rf user1.crt user1.csr user1.key

kubectl config use-context minikube

exit 0


