#!/usr/bin/env bash

#https://sangvhh.net/set-up-kubernetes-cluster-with-kubespray-on-ubuntu-22-04/

#set -x

echo "
alias k='kubectl'
alias KUBECONFIG='~/.kube/config'
alias base='cd /vagrant'
alias ll='ls -al'
" >> /root/.bashrc

cat >> /root/.bashrc <<EOF
function prop {
  key="\${2}="
  rslt=""
  if [[ "\${3}" == "" ]]; then
    rslt=\$(grep "\${key}" "/root/.aws/\${1}" | head -n 1 | cut -d '=' -f2 | sed 's/ //g')
    if [[ "\${rslt}" == "" ]]; then
      key="\${2} = "
      rslt=\$(grep "\${key}" "/root/.aws/\${1}" | head -n 1 | cut -d '=' -f2 | sed 's/ //g')
    fi
  else
    rslt=\$(grep "\${3}" "/root/.aws/\${1}" -A 10 | grep "\${key}" | head -n 1 | tail -n 1 | cut -d '=' -f2 | sed 's/ //g')
    if [[ "\${rslt}" == "" ]]; then
      key="\${2} = "
      rslt=\$(grep "\${3}" "/root/.aws/\${1}" -A 10 | grep "\${key}" | head -n 1 | tail -n 1 | cut -d '=' -f2 | sed 's/ //g')
    fi
  fi
  echo \${rslt}
}
EOF

if [ -d /vagrant ]; then
  cd /vagrant
fi

sudo rm -Rf kubespray
#git clone --single-branch https://github.com/kubernetes-sigs/kubespray.git
git clone https://github.com/kubernetes-sigs/kubespray.git --branch release-2.21
rm -Rf kubespray/inventory/test-cluster

#echo -n "Did you fix ip address in resource/kubespray settings? (Y)"
#read A_ENV
#echo "A_ENV: ${A_ENV}"
#if [[ "${A_ENV}" != "Y" ]]; then
#  exit 1
#fi

cp -rfp kubespray/inventory/sample kubespray/inventory/test-cluster
cp -Rf resource/kubespray/addons.yml kubespray/inventory/test-cluster/group_vars/k8s_cluster/addons.yml
cp -Rf resource/kubespray/k8s-cluster.yml kubespray/inventory/test-cluster/group_vars/k8s_cluster/k8s-cluster.yml

cp -Rf resource/kubespray/inventory.ini kubespray/inventory/test-cluster/inventory.ini
cp -Rf scripts/local/config.cfg /root/.ssh/config

cd kubespray
sudo pip3 install -r requirements.txt
cd ..

#/etc/ansible/ansible.cfg

ansible all -i resource/kubespray/inventory.ini -m ping -u root
ansible all -i resource/kubespray/inventory.ini --list-hosts -u root

# to reset on each node.
#kubeadm reset
ansible-playbook -u root -i resource/kubespray/inventory.ini kubespray/reset.yml \
  --become --become-user=root --extra-vars "reset_confirmation=yes"

iptables --policy INPUT   ACCEPT
iptables --policy OUTPUT  ACCEPT
iptables --policy FORWARD ACCEPT
iptables -Z # zero counters
iptables -F # flush (delete) rules
iptables -X # delete all extra chains
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
rm -Rf $HOME/.kube
#sudo reboot

#declare -a IPS=(192.168.86.90 192.168.86.91 192.168.86.92)
#CONFIG_FILE=inventory/test-cluster/inventory.ini python3 contrib/inventory_builder/inventory.py ${IPS[@]}

#cat inventory/test-cluster/group_vars/all/all.yml
#cat inventory/test-cluster/group_vars/k8s_cluster/k8s-cluster.yml

#cd resource/kubespray
#scp doohee323@master:/Volumes/workspace/etc/tz-k8s-vagrant/kubespray/inventory/test-cluster/group_vars/k8s_cluster/k8s-cluster.yml .
#scp k8s-cluster.yml doohee323@master:/Volumes/workspace/etc/tz-k8s-vagrant/kubespray/inventory/test-cluster/group_vars/k8s_cluster/k8s-cluster.yml
#scp master:/Volumes/workspace/etc/tz-k8s-vagrant/kubespray/inventory/test-cluster/group_vars/k8s_cluster/k8s-cluster.yml k8s-cluster.yml
#scp master:/Volumes/workspace/etc/tz-k8s-vagrant/kubespray/inventory/test-cluster/group_vars/k8s_cluster/addons.yml addons.yml

#export ANSIBLE_PERSISTENT_CONNECT_TIMEOUT=120
#ansible -vvvv -i inventory/test-cluster/inventory.ini all -a "systemctl status sshd" -u root

#ansible-playbook -vvvv -u root -i inventory/test-cluster/inventory.ini -e 'ansible_python_interpreter=/usr/bin/python3' \
#  --private-key /root/.ssh/tz_rsa --become --become-user=root cluster.yml

#apt-add-repository ppa:ansible/ansible
#apt update
#apt install ansible -y

# install k8s
ansible-playbook -u root -i resource/kubespray/inventory.ini \
  --private-key .ssh/tz_rsa --become --become-user=root \
  kubespray/cluster.yml
#ansible-playbook -i resource/kubespray/inventory.ini --become --become-user=root cluster.yml

sudo cp -Rf /root/.kube /home/vagrant/
sudo chown -Rf vagrant:vagrant /home/vagrant/.kube
sudo cp -Rf /root/.kube/config /vagrant/.ssh/kubeconfig_tz-k8s-vagrant

#kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl
#exec bash

kubectl get nodes
kubectl cluster-info

shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

#k delete -f tz-local/resource/standard-storage.yaml
k apply -f tz-local/resource/standard-storage.yaml
k patch storageclass local-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
k get storageclass,pv,pvc

#helm repo add stable https://charts.helm.sh/stable
#helm repo update
#
# nfs
# 1. with helm
#helm install my-release --set nfs.server=192.168.86.90 --set nfs.path=/srv/nfs/mydata stable/nfs-client-provisioner
# 2. with manual
#k apply -f tz-local/resource/dynamic-provisioning/nfs/static-nfs.yaml
#k apply -f tz-local/resource/dynamic-provisioning/nfs/serviceaccount.yaml
#k apply -f tz-local/resource/dynamic-provisioning/nfs/nfs.yaml
#k apply -f tz-local/resource/dynamic-provisioning/nfs/nfs-claim.yaml

#echo "## [ install kubectl ] ######################################################"
#sudo apt-get update && sudo apt-get install -y apt-transport-https gnupg2 curl
#curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
#sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

#echo "## [ install helm3 ] ######################################################"
#sudo curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
#sudo bash get_helm.sh
#sudo rm -Rf get_helm.sh

#sleep 10

#k get po -n kube-system

sudo rm -Rf info

##################################################################
# call nfs dynamic-provisioning
##################################################################
bash tz-local/resource/dynamic-provisioning/nfs/install.sh

##################################################################
# call dashboard install script
##################################################################
#bash tz-local/resource/dashboard/install.sh

##################################################################
# call monitoring install script
##################################################################
bash tz-local/resource/monitoring/install.sh

##################################################################
# call jenkins install script
##################################################################
#bash tz-local/resource/jenkins/install.sh

##################################################################
# call tz-py-crawler app in k8s
##################################################################
#bash tz-local/resource/tz-py-crawler/install.sh

exit 0

bash tz-local/resource/kafka/install.sh