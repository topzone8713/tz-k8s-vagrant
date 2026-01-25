#!/usr/bin/env bash

#https://sangvhh.net/set-up-kubernetes-cluster-with-kubespray-on-ubuntu-22-04/

#set -x

export ANSIBLE_CONFIG=/root/ansible.cfg
export DEBIAN_FRONTEND=noninteractive
echo "
alias k='kubectl'
export ANSIBLE_CONFIG=/root/ansible.cfg
alias KUBECONFIG='~/.kube/config'
alias base='cd /vagrant'
alias ll='ls -al'
" >> /root/.bashrc

cat >> /root/.bashrc <<EOF
function prop {
  key="\${2}=" file="/root/.k8s/\${1}" rslt=\$(grep "\${3:-}" "\$file" -A 10 | grep "\$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g')
  [[ -z "\$rslt" ]] && key="\${2} = " && rslt=\$(grep "\${3:-}" "\$file" -A 10 | grep "\$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g')
  rslt=\$(echo "\$rslt" | tr -d '\n' | tr -d '\r')
  echo "\$rslt"
}
EOF

if [ -d /vagrant ]; then
  cd /vagrant
fi

# Ensure kubectl is installed before using it
if ! command -v kubectl > /dev/null 2>&1; then
  echo "kubectl not found. Installing kubectl..."
  KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
  echo "kubectl installed: $(kubectl version --client --short 2>/dev/null || echo 'version check failed')"
fi

kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl

#kubectl get nodes
#kubectl cluster-info

kubectl create namespace devops-dev
kubectl create namespace devops

shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

#k delete -f tz-local/resource/standard-storage.yaml
k apply -f tz-local/resource/standard-storage.yaml
k patch storageclass local-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
k get storageclass,pv,pvc

#k get po -n kube-system

bash /vagrant/tz-local/resource/docker-repo/install.sh
bash /vagrant/tz-local/resource/dynamic-provisioning/nfs/install.sh
bash /vagrant/tz-local/resource/metallb/install.sh
bash /vagrant/tz-local/resource/ingress_nginx/install.sh

bash /vagrant/tz-local/resource/consul/install.sh
bash /vagrant/tz-local/resource/vault/helm/install.sh

# Need to unseal vault manually !!!!
# vagrant ssh kube-master
# Go to /vagrant/tz-local/resource/vault/helm/install.sh again
# vault operator unseal

echo "####################################################################################"
echo "Need to unseal vault manually with this command in each vault pod."
echo "$> vault operator unseal"
echo ""
echo "--------------------------------------------------------------------------------"
cat /vagrant/resources/unseal.txt
echo "--------------------------------------------------------------------------------"
echo ""
echo "After that, to add slave nodes to k8s cluster"
echo "bash /vagrant/scripts/local/kubespray_add.sh"
echo ""
echo "To go into kube-master"
echo "$> vagrant ssh kube-master"
echo "$> sudo su"
echo "$> cd /vagrant"
echo "####################################################################################"

echo ""
echo "####################################################################################"
echo "Installing monitoring (Prometheus Operator)..."
echo "####################################################################################"
bash /vagrant/tz-local/resource/monitoring/install.sh
bash /vagrant/tz-local/resource/monitoring/rules/update.sh
echo "####################################################################################"
echo "Monitoring installation completed!"
echo "####################################################################################"

exit 0

