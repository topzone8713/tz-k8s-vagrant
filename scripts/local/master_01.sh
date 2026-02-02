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

# Ensure /root/.k8s directory exists (created by master.sh)
if [ ! -d /root/.k8s ]; then
  echo "WARNING: /root/.k8s directory does not exist. Creating from /vagrant/resources..."
  if [ -d /vagrant/resources ]; then
    sudo rm -Rf /root/.k8s
    sudo cp -Rf /vagrant/resources /root/.k8s
    sudo chown -R root:root /root/.k8s
    echo "✓ /root/.k8s directory created"
  else
    echo "ERROR: /vagrant/resources directory does not exist!"
    echo "Cannot create /root/.k8s. The prop function will not work."
    exit 1
  fi
fi

cat >> /root/.bashrc <<EOF
function prop {
  key="\${2}=" file="/root/.k8s/\${1}" rslt=\$([ -f "\$file" ] && grep "\${3:-}" "\$file" -A 10 2>/dev/null | grep "\$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g' || echo "")
  [[ -z "\$rslt" ]] && key="\${2} = " && rslt=\$([ -f "\$file" ] && grep "\${3:-}" "\$file" -A 10 2>/dev/null | grep "\$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g' || echo "")
  rslt=\$(echo "\$rslt" | tr -d '\n' | tr -d '\r')
  echo "\$rslt"
}
EOF

if [ -d /vagrant ]; then
  cd /vagrant
fi

# Fix network routing if needed (use NAT interface for internet access)
# This is critical for downloading kubectl/helm after kubespray execution
echo "=========================================="
echo "Checking and fixing network routing for internet access..."
echo "=========================================="

# Source common network functions
if [ -f /vagrant/scripts/local/common-network.sh ]; then
  source /vagrant/scripts/local/common-network.sh
  fix_and_verify_network "/dev/null" "true" "true"
else
  # Fallback to inline implementation if common-network.sh is not available
  DEFAULT_ROUTES=$(ip route | grep "^default" | wc -l)
  ETH1_DEFAULT=$(ip route | grep "^default.*eth1" | wc -l)
  if [ "$ETH1_DEFAULT" -gt 0 ] || ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "Fixing network routing for internet access..."
    sudo ip route del default via 192.168.0.1 dev eth1 2>/dev/null || true
    sudo ip route del default via 10.0.2.2 dev eth0 2>/dev/null || true
    sudo ip route add default via 10.0.2.2 dev eth0 2>/dev/null || true
    sleep 2
  fi
  
  # Verify internet connectivity after routing fix
  if ! ping -c 3 8.8.8.8 > /dev/null 2>&1; then
    echo "ERROR: Internet connectivity check failed after routing fix!"
    echo "Current routing table:"
    ip route
    echo "Cannot install kubectl/helm without internet access."
    exit 1
  fi
  echo "✓ Internet connectivity verified"
fi

# Ensure kubectl and helm are installed before using them
# Source common network functions if available
if [ -f /vagrant/scripts/local/common-network.sh ]; then
  source /vagrant/scripts/local/common-network.sh
  
  # Install kubectl
  if ! install_kubectl "/dev/null" "true"; then
    echo "ERROR: kubectl installation failed"
    exit 1
  fi
  
  # Install helm
  if ! install_helm "/dev/null" "true"; then
    echo "ERROR: helm installation failed"
    exit 1
  fi
else
  # Fallback to inline implementation if common-network.sh is not available
  if ! command -v kubectl > /dev/null 2>&1; then
    echo "kubectl not found. Installing kubectl..."
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
    echo "kubectl installed: $(kubectl version --client --short 2>/dev/null || echo 'version check failed')"
  fi
  
  if ! command -v helm > /dev/null 2>&1; then
    echo "helm not found. Installing helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    sudo bash get_helm.sh
    sudo rm -f get_helm.sh
    echo "helm installed: $(helm version --short 2>/dev/null || echo 'version check failed')"
  fi
fi

kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl

#kubectl get nodes
#kubectl cluster-info

echo "=========================================="
echo "Creating namespaces..."
echo "=========================================="
kubectl create namespace devops-dev 2>/dev/null || kubectl get namespace devops-dev > /dev/null 2>&1 && echo "Namespace devops-dev already exists" || { echo "ERROR: Failed to create namespace devops-dev"; exit 1; }
kubectl create namespace devops 2>/dev/null || kubectl get namespace devops > /dev/null 2>&1 && echo "Namespace devops already exists" || { echo "ERROR: Failed to create namespace devops"; exit 1; }
echo "✓ Namespaces created"

echo ""
echo "=========================================="
echo "Setting up storage (standard-storage.yaml)..."
echo "=========================================="
# Use kubectl directly instead of alias to avoid issues
# This script runs as root, kubectl will use /root/.kube/config by default
KUBECTL_CMD="kubectl"

#k delete -f tz-local/resource/standard-storage.yaml
if [ ! -f /vagrant/tz-local/resource/standard-storage.yaml ]; then
  echo "ERROR: standard-storage.yaml not found at /vagrant/tz-local/resource/standard-storage.yaml"
  exit 1
fi

if ! $KUBECTL_CMD apply -f /vagrant/tz-local/resource/standard-storage.yaml; then
  echo "ERROR: Failed to apply standard-storage.yaml"
  exit 1
fi
echo "✓ standard-storage.yaml applied"

if ! $KUBECTL_CMD patch storageclass local-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null; then
  echo "WARNING: Failed to patch storageclass local-storage (may already be set)"
fi
echo "✓ StorageClass local-storage configured"

$KUBECTL_CMD get storageclass,pv,pvc
echo ""

echo "=========================================="
echo "Installing infrastructure components..."
echo "=========================================="

# Install docker-repo
echo "[1/4] Installing docker-repo..."
if [ ! -f /vagrant/tz-local/resource/docker-repo/install.sh ]; then
  echo "WARNING: docker-repo/install.sh not found, skipping"
else
  if ! bash /vagrant/tz-local/resource/docker-repo/install.sh; then
    echo "WARNING: docker-repo/install.sh failed, continuing anyway"
  else
    echo "✓ docker-repo installed"
  fi
fi

# Install NFS dynamic provisioning
echo "[2/4] Installing NFS dynamic provisioning..."
if [ ! -f /vagrant/tz-local/resource/dynamic-provisioning/nfs/install.sh ]; then
  echo "WARNING: dynamic-provisioning/nfs/install.sh not found, skipping"
else
  if ! bash /vagrant/tz-local/resource/dynamic-provisioning/nfs/install.sh; then
    echo "WARNING: dynamic-provisioning/nfs/install.sh failed, continuing anyway"
  else
    echo "✓ NFS dynamic provisioning installed"
  fi
fi

# Install MetalLB
echo "[3/4] Installing MetalLB..."
if [ ! -f /vagrant/tz-local/resource/metallb/install.sh ]; then
  echo "WARNING: metallb/install.sh not found, skipping"
else
  if ! bash /vagrant/tz-local/resource/metallb/install.sh; then
    echo "WARNING: metallb/install.sh failed, continuing anyway"
  else
    echo "✓ MetalLB installed"
  fi
fi

# Install Ingress NGINX
echo "[4/4] Installing Ingress NGINX..."
if [ ! -f /vagrant/tz-local/resource/ingress_nginx/install.sh ]; then
  echo "WARNING: ingress_nginx/install.sh not found, skipping"
else
  if ! bash /vagrant/tz-local/resource/ingress_nginx/install.sh; then
    echo "WARNING: ingress_nginx/install.sh failed, continuing anyway"
  else
    echo "✓ Ingress NGINX installed"
  fi
fi

echo ""
echo "=========================================="
echo "Infrastructure components installation completed!"
echo "=========================================="

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

