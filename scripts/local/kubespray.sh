#!/usr/bin/env bash

# Exit on error - 인터넷 연결 실패 시 중지
set -e

#set -x

# Locale 설정 (Ansible locale 에러 해결)
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

export ANSIBLE_CONFIG=/root/ansible.cfg

if [ -d /vagrant ]; then
  cd /vagrant
fi

# Check internet connectivity - 인터넷 연결 확인
echo "=========================================="
echo "Checking internet connectivity..."
echo "=========================================="

# Source common network functions
if [ -f /vagrant/scripts/local/common-network.sh ]; then
  source /vagrant/scripts/local/common-network.sh
  fix_and_verify_network "/dev/null" "true" "true"
  verify_dns_resolution "github.com" "true"
else
  # Fallback to inline implementation if common-network.sh is not available
  if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "Fixing network routing for internet access..."
    sudo ip route del default via 192.168.0.1 dev eth1 2>/dev/null || true
    sudo ip route add default via 10.0.2.2 dev eth0 2>/dev/null || true
    sleep 2
  fi
  
  # Verify internet connectivity after routing fix
  if ! ping -c 3 8.8.8.8 > /dev/null 2>&1; then
    echo "ERROR: Internet connectivity check failed!"
    echo "Cannot proceed without internet access."
    echo "Please check network configuration."
    exit 1
  fi
  
  # Verify DNS resolution
  if ! nslookup github.com > /dev/null 2>&1; then
    echo "ERROR: DNS resolution failed!"
    echo "Cannot resolve github.com. Please check DNS configuration."
    exit 1
  fi
fi

echo "✓ Internet connectivity verified"
echo "=========================================="

sudo rm -Rf kubespray

# Clone kubespray with retry logic
MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if git clone https://github.com/kubernetes-sigs/kubespray.git --branch release-2.26; then
    break
  else
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Failed to clone kubespray (attempt $RETRY_COUNT/$MAX_RETRIES). Retrying in 5 seconds..."
    sleep 5
  fi
done

if [ ! -d kubespray ]; then
  echo "ERROR: Failed to clone kubespray after $MAX_RETRIES attempts"
  exit 1
fi

rm -Rf kubespray/inventory/test-cluster

cp -rfp kubespray/inventory/sample kubespray/inventory/test-cluster
cp -Rf resource/kubespray/addons.yml kubespray/inventory/test-cluster/group_vars/k8s_cluster/addons.yml
cp -Rf resource/kubespray/k8s-cluster.yml kubespray/inventory/test-cluster/group_vars/k8s_cluster/k8s-cluster.yml
cp -Rf resource/kubespray/k8s-net-calico.yml kubespray/inventory/test-cluster/group_vars/k8s_cluster/k8s-net-calico.yml
cp -Rf resource/kubespray/calico-node.yml.j2 kubespray/roles/network_plugin/calico/templates/calico-node.yml.j2

cp -Rf resource/kubespray/inventory.ini kubespray/inventory/test-cluster/inventory.ini
cp -Rf scripts/local/config.cfg /root/.ssh/config

cd kubespray
sudo pip3 install -r requirements.txt
cd ..

#/etc/ansible/ansible.cfg
cat <<EOF > /root/ansible.cfg
[defaults]
roles_path = /vagrant/kubespray/roles
EOF

# Use test-cluster inventory so group_vars (k8s-net-calico.yml etc.) are loaded from
# kubespray/inventory/test-cluster/group_vars/ — not resource/kubespray/
INVENTORY="kubespray/inventory/test-cluster/inventory.ini"
ansible all -i "$INVENTORY" -m ping -u root
ansible all -i "$INVENTORY" --list-hosts -u root

# to reset on each node.
#kubeadm reset
#ansible-playbook -u root -i resource/kubespray/inventory.ini kubespray/reset.yml \
#  --become --become-user=root --extra-vars "reset_confirmation=yes"

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

# install k8s
# Verify all nodes are reachable before running ansible-playbook
echo "Verifying all nodes are reachable..."
if ! ansible all -i "$INVENTORY" -m ping -u root > /dev/null 2>&1; then
  echo "ERROR: Not all nodes are reachable via SSH!"
  echo "Please check SSH connectivity to all nodes."
  ansible all -i "$INVENTORY" -m ping -u root
  exit 1
fi

echo "All nodes are reachable. Starting Kubernetes cluster installation..."
cd kubespray
ansible-playbook -u root -i inventory/test-cluster/inventory.ini \
  --private-key /root/.ssh/tz_rsa --become --become-user=root \
  cluster.yml
cd ..
#ansible-playbook -i resource/kubespray/inventory.ini --become --become-user=root cluster.yml

sudo cp -Rf /root/.kube /home/topzone/
sudo chown -Rf topzone:topzone /home/topzone/.kube
sudo cp -Rf /root/.kube /home/vagrant/
sudo chown -Rf vagrant:vagrant /home/vagrant/.kube

# Determine kubeconfig filename based on project directory name
# Extract project name from /vagrant path (e.g., /vagrant -> tz-k8s-vagrant)
# /vagrant is mounted from host, so we need to get the actual project directory name
# Try multiple methods to get the project name
if [ -f /vagrant/info ]; then
  # Try to extract from info file if it exists
  PROJECT_NAME=$(grep -E "^PROJECT_NAME=|^WORKING_DIR=" /vagrant/info 2>/dev/null | head -1 | sed -E 's/.*=//' | xargs basename 2>/dev/null || echo "")
fi

# If PROJECT_NAME is still empty, try to get from /vagrant path
if [ -z "$PROJECT_NAME" ]; then
  # /vagrant itself is the project directory, so we need to check if there's a way to get the host path
  # Since /vagrant is a mount point, we'll use a default or try to infer from common patterns
  # Check if there's a bootstrap.sh or other identifying files
  if [ -f /vagrant/bootstrap.sh ]; then
    # Try to extract from bootstrap.sh WORKING_DIR if possible, or use default
    PROJECT_NAME="tz-k8s-vagrant"
  else
    PROJECT_NAME="tz-k8s-vagrant"
  fi
fi

# Fallback to default if still empty
PROJECT_NAME=${PROJECT_NAME:-"tz-k8s-vagrant"}

KUBECONFIG_FILENAME="kubeconfig_${PROJECT_NAME}"
KUBECONFIG_DIR="/vagrant/.ssh"
KUBECONFIG_PATH="${KUBECONFIG_DIR}/${KUBECONFIG_FILENAME}"

# Ensure .ssh directory exists
sudo mkdir -p "${KUBECONFIG_DIR}"
sudo chmod 700 "${KUBECONFIG_DIR}"

sudo cp -Rf /root/.kube/config "${KUBECONFIG_PATH}"

sed -ie "s|127.0.0.1|192.168.0.100|g" "${KUBECONFIG_PATH}"

echo "## [ install kubectl ] ######################################################"
sudo apt-get update && sudo apt-get install -y apt-transport-https gnupg2 curl

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  aarch64|arm64)
    ARCH="arm64"
    ;;
  x86_64|amd64)
    ARCH="amd64"
    ;;
  *)
    ARCH="amd64"
    ;;
esac

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

echo "## [ install helm3 ] ######################################################"
sudo curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
sudo bash get_helm.sh
sudo rm -Rf get_helm.sh

echo "## [ Calico VXLAN configuration ] ######################################################"
echo "Calico VXLAN configuration is handled by k8s-net-calico.yml during kubespray installation"
echo "VXLAN mode is used instead of IPIP/BGP to prevent routing table modifications"
echo "To verify, check Calico settings after installation:"
echo "  kubectl get ippool default-pool -o jsonpath='{.spec.vxlanMode}'"
echo "  kubectl get cm calico-config -n kube-system -o jsonpath='{.data.calico_backend}'"

exit 0

