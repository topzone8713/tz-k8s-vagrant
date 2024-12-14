#!/usr/bin/env bash

#https://sangvhh.net/set-up-kubernetes-cluster-with-kubespray-on-ubuntu-22-04/

#set -x

export ANSIBLE_CONFIG=/root/ansible.cfg
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

echo "##########################################"
echo "Need to unseal vault manually !!!!"
cat /vagrant/resources/unseal.txt
echo "After that, "
echo "bash /vagrant/scripts/k8s_addtion.sh"
echo "##########################################"

exit 0

