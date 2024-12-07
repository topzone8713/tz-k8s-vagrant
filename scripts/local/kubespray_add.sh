#!/usr/bin/env bash

# add a new node
#https://www.techbeatly.com/adding-new-nodes-to-kubespray-managed-kubernetes-cluster/

#set -x

if [ -d /vagrant ]; then
  cd /vagrant
fi

cd kubespray
#ansible all -i resource/kubespray/inventory.ini -m ping -u root
ansible all -i resource/kubespray/inventory_add.ini -m ping -u root

#ansible-playbook -i inventory/test-cluster/hosts.yaml cluster.yml -b -become-user=root -l node3
ansible-playbook -u root -i resource/kubespray/inventory_add.ini \
  --private-key .ssh/tz_rsa --become --become-user=root \
  kubespray/cluster.yml -b -l kube-slave-4

#ansible-playbook -u root -i resource/kubespray/inventory_add.ini \
#  --private-key .ssh/tz_rsa --become --become-user=root \
#    kubespray/reset.yml -b -l kube-slave-4 --extra-vars "reset_confirmation=yes"

#validate_certs: true
#=>
#validate_certs: false

echo "##########################################"
echo "Next step !!!"
echo "bash scripts/k8s_addtion.sh"
echo "##########################################"

exit 0

