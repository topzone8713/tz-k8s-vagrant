#!/usr/bin/env bash

# add a new node
#https://www.techbeatly.com/adding-new-nodes-to-kubespray-managed-kubernetes-cluster/

# Check if running as root, if not, re-execute with sudo
if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges. Re-executing with sudo..."
    exec sudo bash "$0" "$@"
fi

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Exit if any command in a pipeline fails

# Locale settings (same as kubespray.sh)
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Ansible configuration (same as kubespray.sh)
export ANSIBLE_CONFIG=/root/ansible.cfg

if [ -d /vagrant ]; then
  cd /vagrant
fi

# Update /etc/hosts with all nodes from inventory_add.ini
echo "=== Step 0: Updating /etc/hosts with all nodes ==="
if [ -f /vagrant/resource/kubespray/inventory_add.ini ]; then
  # Extract hostname and IP from inventory_add.ini
  # Format: kube-slave-1 ansible_host=192.168.0.110 ...
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue
    
    # Extract hostname and IP
    if [[ "$line" =~ ^([a-zA-Z0-9-]+)[[:space:]]+ansible_host=([0-9.]+) ]]; then
      HOSTNAME="${BASH_REMATCH[1]}"
      IP="${BASH_REMATCH[2]}"
      
      # Remove existing entry if present
      sed -i "/[[:space:]]${HOSTNAME}[[:space:]]*$/d" /etc/hosts 2>/dev/null || true
      
      # Add new entry
      echo "${IP}    ${HOSTNAME}" | tee -a /etc/hosts > /dev/null
      echo "  Added: ${IP} -> ${HOSTNAME}"
    fi
  done < /vagrant/resource/kubespray/inventory_add.ini
  
  echo "✓ /etc/hosts updated"
else
  echo "⚠ WARNING: inventory_add.ini not found, skipping /etc/hosts update"
fi
echo ""

# Verify SSH key exists and has correct permissions
# Note: This script assumes SSH keys already exist (copied from my-ubuntu to my-mac/my-mac2)
echo "=== Step 0.5: Verifying SSH key permissions ==="
MYKEY=tz_rsa

# Verify SSH key file exists (must already exist, do not create or copy)
if [ ! -f /root/.ssh/${MYKEY} ]; then
  echo "✗ ERROR: SSH key file not found: /root/.ssh/${MYKEY}"
  echo "  This script assumes SSH keys already exist."
  echo "  Please ensure SSH keys are copied from my-ubuntu to my-mac/my-mac2 first."
  exit 1
fi

# Ensure /root/.ssh directory has proper permissions
if [ -d /root/.ssh ]; then
  chmod 700 /root/.ssh
else
  echo "✗ ERROR: /root/.ssh directory not found"
  exit 1
fi

# Verify and fix SSH key file permissions (if needed)
if [ -f /root/.ssh/${MYKEY} ]; then
  chmod 600 /root/.ssh/${MYKEY}
  chown root:root /root/.ssh/${MYKEY}
  echo "✓ SSH private key verified: /root/.ssh/${MYKEY}"
  ls -la /root/.ssh/${MYKEY} | head -1
else
  echo "✗ ERROR: SSH private key file not found: /root/.ssh/${MYKEY}"
  exit 1
fi

if [ -f /root/.ssh/${MYKEY}.pub ]; then
  chmod 644 /root/.ssh/${MYKEY}.pub
  chown root:root /root/.ssh/${MYKEY}.pub
  echo "✓ SSH public key verified: /root/.ssh/${MYKEY}.pub"
else
  echo "⚠ WARNING: SSH public key file not found: /root/.ssh/${MYKEY}.pub (non-critical)"
fi

# Ensure all files in /root/.ssh have correct permissions
chown -R root:root /root/.ssh
chmod 700 /root/.ssh
find /root/.ssh -type f -name "${MYKEY}" -exec chmod 600 {} \;
find /root/.ssh -type f -name "${MYKEY}.pub" -exec chmod 644 {} \;

echo "✓ SSH key setup completed"
echo ""

# Note: Slave nodes should already have kube-master's public key in authorized_keys
# This is set up by base.sh during VM provisioning on my-mac/my-mac2
# Since kube-master is on my-ubuntu and slave nodes are on my-mac/my-mac2,
# we cannot directly add keys from kube-master. The keys must be pre-configured.
echo "=== Step 0.6: SSH Key Authentication Setup ==="
echo "SSH key authentication configuration:"
echo "  - kube-master uses: /root/.ssh/tz_rsa (private key)"
echo "  - Slave nodes need: /root/.ssh/authorized_keys with matching public key"
echo "  - This should be set up by base.sh during VM provisioning"
echo ""
echo "If slave nodes are unreachable, ensure:"
echo "  1. Slave nodes have /root/.ssh/authorized_keys with kube-master's public key"
echo "  2. The public key matches: /root/.ssh/tz_rsa.pub on kube-master"
echo "  3. Slave nodes are accessible from kube-master via network (192.168.0.x)"
echo ""

echo "=== Step 0.7: Prepare add-cluster inventory and group_vars (match existing Calico) ==="
if [ ! -d /vagrant/kubespray ]; then
  echo "ERROR: kubespray directory not found. Run kubespray.sh first."
  exit 1
fi
ADD_INV_DIR="/vagrant/kubespray/inventory/add-cluster"
ADD_GROUP_VARS="${ADD_INV_DIR}/group_vars/k8s_cluster"
mkdir -p "${ADD_GROUP_VARS}"
cp -f /vagrant/resource/kubespray/inventory_add.ini "${ADD_INV_DIR}/inventory.ini"
cp -f /vagrant/resource/kubespray/k8s-net-calico.yml "${ADD_GROUP_VARS}/"
cp -f /vagrant/resource/kubespray/k8s-cluster.yml "${ADD_GROUP_VARS}/"
cp -f /vagrant/resource/kubespray/addons.yml "${ADD_GROUP_VARS}/"
cp -f /vagrant/resource/kubespray/calico-node.yml.j2 /vagrant/kubespray/roles/network_plugin/calico/templates/calico-node.yml.j2
INVENTORY="${ADD_INV_DIR}/inventory.ini"
echo "  Using inventory: ${INVENTORY}"
echo "  group_vars: k8s-net-calico, k8s-cluster, addons (calico_ipip_mode=Never, vxlan)"
echo "✓ add-cluster inventory ready"
echo ""

#ansible all -i /vagrant/resource/kubespray/inventory.ini -m ping -u root
echo "=== Step 1: Testing connectivity to all nodes ==="
# Note: --private-key is not needed here because inventory already has
# ansible_ssh_private_key_file=/root/.ssh/tz_rsa set for each host
ansible all -i "${INVENTORY}" -m ping -u root || {
    echo "ERROR: Failed to connect to one or more nodes"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Ensure SSH keys are copied from my-ubuntu to my-mac/my-mac2"
    echo "  2. Ensure slave nodes have /root/.ssh/authorized_keys with the public key"
    echo "  3. Check if slave nodes are running and accessible via network"
    echo "  4. Verify SSH key file: ls -la /root/.ssh/tz_rsa"
    echo ""
    echo "Checking SSH key file..."
    ls -la /root/.ssh/tz_rsa 2>/dev/null || echo "SSH key file not found"
    exit 1
}

#ansible-playbook -u root -i /vagrant/resource/kubespray/inventory_add.ini /vagrant/kubespray/reset.yml \
#  --become --become-user=root --extra-vars "reset_confirmation=yes"

echo "=== Step 2: Installing Kubernetes cluster with kubespray ==="

# Ensure kubespray directory exists and is set up (same as kubespray.sh)
if [ ! -d /vagrant/kubespray ]; then
  echo "ERROR: kubespray directory not found. Please run kubespray.sh first to clone kubespray."
  exit 1
fi

# Create ansible.cfg with roles_path (same as kubespray.sh)
cat <<EOF > /root/ansible.cfg
[defaults]
roles_path = /vagrant/kubespray/roles
EOF

# Use add-cluster inventory (includes group_vars) so Calico vars match existing cluster
cd /vagrant/kubespray
ansible-playbook -u root -i "${INVENTORY}" \
  --private-key /root/.ssh/tz_rsa --become --become-user=root \
  cluster.yml || {
    echo "ERROR: Kubernetes cluster installation failed"
    cd /vagrant
    exit 1
  }
cd /vagrant

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
ansible-playbook -u root -i "${INVENTORY}" /vagrant/kubespray/playbooks/containerd.yml \
  --private-key /root/.ssh/tz_rsa --become --become-user=root || {
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
  --private-key /root/.ssh/tz_rsa --become --become-user=root \
    /vagrant/kubespray/cluster.yml -b -l kube-slave-4

ansible-playbook -u root -i /vagrant/resource/kubespray/inventory_add.ini \
  --private-key /root/.ssh/tz_rsa --become --become-user=root \
    /vagrant/kubespray/cluster.yml -b -l kube-slave-4 --extra-vars "reset_confirmation=yes"

#validate_certs: true
#=>
#validate_certs: false

