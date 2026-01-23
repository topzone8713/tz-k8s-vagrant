#!/usr/bin/env bash

# add a new node
#https://www.techbeatly.com/adding-new-nodes-to-kubespray-managed-kubernetes-cluster/

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Exit if any command in a pipeline fails

#ansible all -i /vagrant/resource/kubespray/inventory.ini -m ping -u root
echo "=== Step 1: Testing connectivity to all nodes ==="
ansible all -i /vagrant/resource/kubespray/inventory_add.ini -m ping -u root || {
    echo "ERROR: Failed to connect to one or more nodes"
    exit 1
}

#ansible-playbook -u root -i /vagrant/resource/kubespray/inventory_add.ini /vagrant/kubespray/reset.yml \
#  --become --become-user=root --extra-vars "reset_confirmation=yes"

echo "=== Step 2: Installing Kubernetes cluster with kubespray ==="
ansible-playbook -u root -i /vagrant/resource/kubespray/inventory_add.ini \
  --private-key .ssh/tz_rsa --become --become-user=root \
  /vagrant/kubespray/cluster.yml || {
    echo "ERROR: Kubernetes cluster installation failed"
    exit 1
}

#cat /etc/containerd/config.toml
echo "=== Step 3: Configuring containerd ==="
echo "Copying config.toml and containerd.yml to kubespray playbooks directory..."
cp -Rf /vagrant/resource/kubespray/config.toml /vagrant/kubespray/playbooks/config.toml || {
    echo "ERROR: Failed to copy config.toml"
    exit 1
}
cp -Rf /vagrant/resource/kubespray/containerd.yml /vagrant/kubespray/playbooks/containerd.yml || {
    echo "ERROR: Failed to copy containerd.yml"
    exit 1
}

echo "Applying containerd configuration to all nodes..."
ansible-playbook -u root -i /vagrant/resource/kubespray/inventory_add.ini /vagrant/kubespray/playbooks/containerd.yml \
  --become --become-user=root || {
    echo "ERROR: Containerd configuration failed"
    echo "Please check the error above and fix the issue before proceeding"
    exit 1
}

echo "=== Step 4: Containerd configuration completed successfully ==="

#ansible-playbook -u root -i /vagrant/resource/kubespray/inventory_add.ini /vagrant/kubespray/playbooks/containerd.yml \
#  --become --become-user=root -b -l kube-master

echo "=== Step 5: Installing additional infrastructure (Vault, Harbor, ArgoCD, Jenkins) ==="
bash /vagrant/scripts/k8s_addtion.sh || {
    echo "ERROR: Additional infrastructure installation failed"
    exit 1
}

echo "=== All steps completed successfully ==="
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

