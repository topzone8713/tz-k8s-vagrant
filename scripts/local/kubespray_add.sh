#!/usr/bin/env bash

# add a new node
#https://www.techbeatly.com/adding-new-nodes-to-kubespray-managed-kubernetes-cluster/

#set -x

#ansible all -i /vagrant/resource/kubespray/inventory.ini -m ping -u root
ansible all -i /vagrant/resource/kubespray/inventory_add.ini -m ping -u root

#ansible-playbook -u root -i /vagrant/resource/kubespray/inventory_add.ini /vagrant/kubespray/reset.yml \
#  --become --become-user=root --extra-vars "reset_confirmation=yes"

ansible-playbook -u root -i /vagrant/resource/kubespray/inventory_add.ini \
  --private-key .ssh/tz_rsa --become --become-user=root \
  /vagrant/kubespray/cluster.yml

#cat /etc/containerd/config.toml
cp -Rf /vagrant/resource/kubespray/config.toml /vagrant/kubespray/playbooks/config.toml
cp -Rf /vagrant/resource/kubespray/containerd.yml /vagrant/kubespray/playbooks/containerd.yml
ansible-playbook -u root -i /vagrant/resource/kubespray/inventory_add.ini /vagrant/kubespray/playbooks/containerd.yml \
  --become --become-user=root

#ansible-playbook -u root -i /vagrant/resource/kubespray/inventory_add.ini /vagrant/kubespray/playbooks/containerd.yml \
#  --become --become-user=root -b -l kube-master

bash /vagrant/scripts/k8s_addtion.sh

exit 0

#ansible-playbook -i inventory/test-cluster/hosts.yaml cluster.yml -b -become-user=root -l node3
ansible-playbook -u root -i /vagrant/resource/kubespray/inventory_add.ini \
  --private-key .ssh/tz_rsa --become --become-user=root \
  /vagrant/kubespray/cluster.yml -b -l kube-slave-4

ansible-playbook -u root -i /vagrant/resource/kubespray/inventory_add.ini \
  --private-key .ssh/tz_rsa --become --become-user=root \
    /vagrant/kubespray/cluster.yml -b -l kube-slave-4 --extra-vars "reset_confirmation=yes"

#validate_certs: true
#=>
#validate_certs: false

