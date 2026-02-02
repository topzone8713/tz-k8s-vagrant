#!/usr/bin/env bash

# Exit on error - 설치 실패 시 중지
set -e

#set -x

##################################################################
# k8s base
##################################################################
export DEBIAN_FRONTEND=noninteractive

# Log file for debugging (use /tmp if /var/log is not writable)
LOG_FILE="/tmp/base.sh.log"
if [ -w /var/log ]; then
  LOG_FILE="/var/log/base.sh.log"
fi
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/base.sh.log"
echo "==========================================" | tee -a "$LOG_FILE"
echo "base.sh started at $(date)" | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"

if [ -d /vagrant ]; then
  cd /vagrant
fi

sudo groupadd topzone 2>/dev/null || true
sudo useradd -g topzone -d /home/topzone -s /bin/bash -m topzone 2>/dev/null || true
cat <<EOF > pass.txt
topzone:topzone
EOF
sudo chpasswd < pass.txt
sudo mkdir -p /home/topzone/.ssh &&
  sudo chown -Rf topzone:topzone /home/topzone

MYKEY=tz_rsa
# Use existing keys only; never generate on slave. Fail if missing.
if [ ! -f /vagrant/.ssh/${MYKEY}.pub ]; then
  echo "ERROR: /vagrant/.ssh/${MYKEY}.pub not found. Add .ssh/tz_rsa.pub in project root before provisioning." | tee -a "$LOG_FILE"
  exit 1
fi
if [ ! -f /vagrant/.ssh/${MYKEY} ]; then
  echo "ERROR: /vagrant/.ssh/${MYKEY} not found. Add .ssh/tz_rsa in project root before provisioning." | tee -a "$LOG_FILE"
  exit 1
fi

sudo mkdir -p /root/.ssh
sudo chmod 700 /root/.ssh
sudo cp -f /vagrant/.ssh/${MYKEY} /root/.ssh/${MYKEY}
sudo chmod 600 /root/.ssh/${MYKEY}
sudo cp -f /vagrant/.ssh/${MYKEY}.pub /root/.ssh/${MYKEY}.pub
sudo chmod 644 /root/.ssh/${MYKEY}.pub

PUB_KEY_CONTENT=$(cat /root/.ssh/${MYKEY}.pub)
sudo touch /root/.ssh/authorized_keys
if ! grep -qF "$PUB_KEY_CONTENT" /root/.ssh/authorized_keys 2>/dev/null; then
  echo "$PUB_KEY_CONTENT" | sudo tee -a /root/.ssh/authorized_keys > /dev/null
fi
sudo chown -R root:root /root/.ssh
sudo chmod 700 /root/.ssh
sudo find /root/.ssh -type f -exec chmod 600 {} \;

# Append tz_rsa.pub to vagrant's authorized_keys (do not overwrite)
sudo mkdir -p /home/vagrant/.ssh
sudo touch /home/vagrant/.ssh/authorized_keys
if ! grep -qF "$PUB_KEY_CONTENT" /home/vagrant/.ssh/authorized_keys 2>/dev/null; then
  echo "$PUB_KEY_CONTENT" | sudo tee -a /home/vagrant/.ssh/authorized_keys > /dev/null
fi
sudo chown vagrant:vagrant /home/vagrant/.ssh /home/vagrant/.ssh/authorized_keys
sudo chmod 700 /home/vagrant/.ssh
sudo chmod 600 /home/vagrant/.ssh/authorized_keys

# topzone gets copy of root .ssh (for any scripts using topzone)
sudo rm -Rf /home/topzone/.ssh
sudo cp -Rf /root/.ssh /home/topzone/.ssh
sudo chown -Rf topzone:topzone /home/topzone/.ssh
sudo chmod -Rf 700 /home/topzone/.ssh
sudo find /home/topzone/.ssh -type f -exec chmod 600 {} \; 2>/dev/null || true

sudo sh -c "cat <<EOF >> /etc/resolv.conf
nameserver 1.1.1.1 #cloudflare DNS
nameserver 8.8.8.8 #Google DNS
EOF"

sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Swap 파일 생성 (2GB) - 메모리 부족 시 사용
if [ ! -f /swapfile ]; then
  echo "Swap 파일 생성 중..."
  sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile

  # /etc/fstab에 추가 (위에서 삭제했으므로 다시 추가)
  if ! grep -q "/swapfile" /etc/fstab; then
    echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
  fi

  echo "Swap 설정 완료:"
  free -h
fi
#sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo apt-get update
sudo apt install -y python3 python3-pip net-tools git runc

#sudo apt install --reinstall ca-certificates -y

sudo tee /etc/modules-load.d/containerd.conf << EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/kubernetes.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

#sudo ufw enable
#sudo ufw allow 22
#sudo ufw allow 6443
sudo ufw disable

apt update
apt install -y nfs-server nfs-common
mkdir -p /srv/nfs 2>/dev/null || true
sudo chown nobody:nogroup /srv/nfs
sudo chmod 0777 /srv/nfs
cat << EOF >> /etc/exports
/srv/nfs 192.168.0.0/24(rw,no_subtree_check,no_root_squash)
EOF
systemctl enable --now nfs-server
exportfs -ar

apt install ntp -y
systemctl start ntp
systemctl enable ntp
#ntpdate pool.ntp.org

# Check internet connectivity before installing tools
echo "[$(date)] Checking internet connectivity..." | tee -a "$LOG_FILE"

# Source common network functions
if [ -f /vagrant/scripts/local/common-network.sh ]; then
  source /vagrant/scripts/local/common-network.sh
  fix_and_verify_network "$LOG_FILE" "false" "true"
else
  # Fallback to inline implementation if common-network.sh is not available
  # Fix network routing if needed (use NAT interface for internet access)
  DEFAULT_ROUTES=$(ip route | grep "^default" | wc -l)
  ETH1_DEFAULT=$(ip route | grep "^default.*eth1" | wc -l)
  if [ "$ETH1_DEFAULT" -gt 0 ] || ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "[$(date)] Fixing network routing for internet access..." | tee -a "$LOG_FILE"
    sudo ip route del default via 192.168.0.1 dev eth1 2>/dev/null || true
    sudo ip route del default via 10.0.2.2 dev eth0 2>/dev/null || true
    sudo ip route add default via 10.0.2.2 dev eth0 2>/dev/null || true
    sleep 2
  fi
  
  # Verify internet connectivity after routing fix
  if ! ping -c 3 8.8.8.8 > /dev/null 2>&1; then
    echo "[$(date)] ERROR: Internet connectivity check failed!" | tee -a "$LOG_FILE"
    echo "ERROR: Internet connectivity check failed!" >&2
    echo "Current routing table:" >&2
    ip route >&2
    echo "Cannot install kubectl/helm without internet access." >&2
    exit 1
  fi
  echo "[$(date)] Internet connectivity verified" | tee -a "$LOG_FILE"
fi

# Install kubectl (required for all nodes)
echo "[$(date)] Starting kubectl installation check..." | tee -a "$LOG_FILE"
if [ -f /vagrant/scripts/local/common-network.sh ]; then
  source /vagrant/scripts/local/common-network.sh
  if ! install_kubectl "$LOG_FILE" "false"; then
    echo "ERROR: kubectl installation failed" >&2
    exit 1
  fi
else
  # Fallback to inline implementation if common-network.sh is not available
  if ! command -v kubectl > /dev/null 2>&1; then
    echo "##############################################"
    echo "Installing kubectl..."
    echo "##############################################"
    echo "[$(date)] kubectl not found, installing..." | tee -a "$LOG_FILE"
    
    # Get kubectl version (verify internet access)
    if ! KUBECTL_VERSION=$(curl -L -s --max-time 10 https://dl.k8s.io/release/stable.txt); then
      echo "[$(date)] ERROR: Failed to get kubectl version from internet" | tee -a "$LOG_FILE"
      echo "ERROR: Failed to get kubectl version from internet" >&2
      exit 1
    fi
    
    # Detect architecture for fallback
    local ARCH
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

    # Download and install kubectl (simplified fallback)
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
    echo "[$(date)] kubectl installed successfully" | tee -a "$LOG_FILE"
  else
    echo "[$(date)] kubectl already installed" | tee -a "$LOG_FILE"
  fi
fi

# Install helm (required for all nodes)
echo "[$(date)] Starting helm installation check..." | tee -a "$LOG_FILE"
if [ -f /vagrant/scripts/local/common-network.sh ]; then
  # Source again in case it wasn't sourced earlier
  source /vagrant/scripts/local/common-network.sh
  if ! install_helm "$LOG_FILE" "false"; then
    echo "ERROR: helm installation failed" >&2
    exit 1
  fi
else
  # Fallback to inline implementation if common-network.sh is not available
  if ! command -v helm > /dev/null 2>&1; then
    echo "##############################################"
    echo "Installing helm..."
    echo "##############################################"
    echo "[$(date)] helm not found, installing..." | tee -a "$LOG_FILE"
    
    # Download and install helm (simplified fallback)
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    sudo bash get_helm.sh
    sudo rm -f get_helm.sh
    echo "[$(date)] helm installed successfully" | tee -a "$LOG_FILE"
  else
    echo "[$(date)] helm already installed" | tee -a "$LOG_FILE"
  fi
fi

echo "[$(date)] base.sh completed successfully" | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"
echo ""
echo "base.sh execution completed successfully"
echo "Log file: $LOG_FILE"

echo "##############################################"
echo "Ready to be added to k8s"
echo "##############################################"
# Display info file if it exists (may not exist during initial provisioning)
# Note: This is informational only, errors reading info file should not fail provisioning
# Use explicit error handling to prevent set -e from causing script failure
if [ -f /vagrant/info ]; then
  # Temporarily disable set -e for this command to prevent failure
  set +e
  cat /vagrant/info 2>/dev/null
  CAT_EXIT=$?
  set -e
  if [ $CAT_EXIT -ne 0 ]; then
    echo "Info file exists but could not be read (non-critical)"
  fi
else
  echo "Info file not yet created (will be created after all VMs are up)"
fi

# manual test
#sudo mount -t nfs 192.168.0.200:/srv/nfs /mnt
## done

# Update /etc/hosts (use sudo tee to avoid permission issues)
check_host=`cat /etc/hosts | grep 'kube-master'`
if [[ "${check_host}" == "" ]]; then
cat <<EOF | sudo tee -a /etc/hosts > /dev/null
192.168.0.100   kube-master
192.168.0.101   kube-node-1
192.168.0.102   kube-node-2

192.168.0.110   kube-slave-1
192.168.0.112   kube-slave-2
192.168.0.113   kube-slave-3

192.168.0.210   kube-slave-4
192.168.0.212   kube-slave-5
192.168.0.213   kube-slave-6

192.168.0.200   test.default.topzone-k8s.topzone.me consul.default.topzone-k8s.topzone.me vault.default.topzone-k8s.topzone.me
192.168.0.200   consul-server.default.topzone-k8s.topzone.me argocd.default.topzone-k8s.topzone.me
192.168.0.200   jenkins.default.topzone-k8s.topzone.me harbor.harbor.topzone-k8s.topzone.me
192.168.0.200   grafana.default.topzone-k8s.topzone.me prometheus.default.topzone-k8s.topzone.me alertmanager.default.topzone-k8s.topzone.me
192.168.0.200   grafana.default.topzone-k8s.topzone.me prometheus.default.topzone-k8s.topzone.me alertmanager.default.topzone-k8s.topzone.me
192.168.0.200   vagrant-demo-app.devops-dev.topzone-k8s.topzone.me

EOF
fi

