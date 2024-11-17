#!/usr/bin/env bash

#set -x
shopt -s expand_aliases
alias k='kubectl'

brew install kubectl
brew install helm

helm repo add stable https://charts.helm.sh/stable
helm repo update
k create namespace ingress-nginx
helm install ingress-nginx stable/nginx-ingress -n ingress-nginx
helm uninstall ingress-nginx stable/nginx-ingress

k create namespace cert-manager

k apply --validate=false -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.12/deploy/manifests/00-crds.yaml
k label namespace cert-manager certmanager.k8s.io/disable-validation=true

helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v0.12.0
  # --set installCRDs=true

k get pods -n cert-manager
k get services -n cert-manager

helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update
k create namespace cattle-system
helm install rancher rancher-stable/rancher \
  -n cattle-system \
  --set hostname=rancher.localdev

k get services -n cattle-system
k get pods -n cattle-system
k get ingresses -n cattle-system

# in my macos
sudo vi /etc/hosts
127.0.0.1   rancher.localdev

curl http://rancher.localdev

echo '
##[ Rancher ]##########################################################
- url: http://rancher.localdev


#######################################################################
' >> /vagrant/info
cat /vagrant/info

