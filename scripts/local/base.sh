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
# Ensure /root/.ssh directory exists with proper permissions
sudo mkdir -p /root/.ssh
sudo chmod 700 /root/.ssh
# Copy SSH keys from /vagrant/.ssh to /root/.ssh
if [ -f /vagrant/.ssh/${MYKEY} ]; then
  sudo cp -f /vagrant/.ssh/${MYKEY} /root/.ssh/${MYKEY}
  sudo chmod 600 /root/.ssh/${MYKEY}
fi
if [ -f /vagrant/.ssh/${MYKEY}.pub ]; then
  sudo cp -f /vagrant/.ssh/${MYKEY}.pub /root/.ssh/${MYKEY}.pub
  sudo chmod 644 /root/.ssh/${MYKEY}.pub
fi
sudo touch /home/topzone/.ssh/authorized_keys
sudo chown topzone:topzone /home/topzone/.ssh/authorized_keys
if [ -f /root/.ssh/authorized_keys ]; then
  sudo cp /home/topzone/.ssh/authorized_keys /root/.ssh/authorized_keys
else
  sudo touch /root/.ssh/authorized_keys
  sudo cp /home/topzone/.ssh/authorized_keys /root/.ssh/authorized_keys
fi
if [ -f /root/.ssh/${MYKEY}.pub ]; then
  sudo sh -c "cat /root/.ssh/${MYKEY}.pub >> /root/.ssh/authorized_keys"
fi
sudo chown -R root:root /root/.ssh
sudo chmod -Rf 600 /root/.ssh
sudo chmod 700 /root/.ssh
rm -Rf /home/topzone/.ssh \
  && cp -Rf /root/.ssh /home/topzone/.ssh \
  && chown -Rf topzone:topzone /home/topzone/.ssh \
  && chmod -Rf 700 /home/topzone/.ssh \
  && chmod -Rf 600 /home/topzone/.ssh/*

cat <<EOF >> /etc/resolv.conf
nameserver 1.1.1.1 #cloudflare DNS
nameserver 8.8.8.8 #Google DNS
EOF

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
/srv/nfs 192.168.86.0/24(rw,no_subtree_check,no_root_squash)
EOF
systemctl enable --now nfs-server
exportfs -ar

apt install ntp -y
systemctl start ntp
systemctl enable ntp
#ntpdate pool.ntp.org

# Install kubectl (required for all nodes)
echo "[$(date)] Starting kubectl installation check..." | tee -a "$LOG_FILE"
if ! command -v kubectl > /dev/null 2>&1; then
  echo "##############################################"
  echo "Installing kubectl..."
  echo "##############################################"
  echo "[$(date)] kubectl not found, installing..." | tee -a "$LOG_FILE"
  
  # Get kubectl version
  KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  if [ -z "$KUBECTL_VERSION" ]; then
    echo "[$(date)] ERROR: Failed to get kubectl version" | tee -a "$LOG_FILE"
    echo "ERROR: Failed to get kubectl version" >&2
    exit 1
  fi
  
  # Download kubectl
  if ! curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; then
    echo "[$(date)] ERROR: Failed to download kubectl" | tee -a "$LOG_FILE"
    echo "ERROR: Failed to download kubectl" >&2
    exit 1
  fi
  
  echo "[$(date)] kubectl downloaded successfully" | tee -a "$LOG_FILE"
  
  # Install kubectl
  if ! sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; then
    echo "[$(date)] ERROR: Failed to install kubectl" | tee -a "$LOG_FILE"
    echo "ERROR: Failed to install kubectl" >&2
    rm -f kubectl
    exit 1
  fi
  
  rm -f kubectl
  
  # Verify installation
  if ! kubectl version --client --short > /dev/null 2>&1; then
    echo "[$(date)] ERROR: kubectl installation verification failed" | tee -a "$LOG_FILE"
    echo "ERROR: kubectl installation verification failed" >&2
    exit 1
  fi
  
  echo "kubectl installed: $(kubectl version --client --short)"
  echo "[$(date)] kubectl installed successfully" | tee -a "$LOG_FILE"
else
  echo "kubectl is already installed: $(kubectl version --client --short 2>/dev/null || echo 'version check failed')"
  echo "[$(date)] kubectl already installed" | tee -a "$LOG_FILE"
fi

# Install helm (required for all nodes)
echo "[$(date)] Starting helm installation check..." | tee -a "$LOG_FILE"
if ! command -v helm > /dev/null 2>&1; then
  echo "##############################################"
  echo "Installing helm..."
  echo "##############################################"
  echo "[$(date)] helm not found, installing..." | tee -a "$LOG_FILE"
  
  # Download helm install script
  if ! curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3; then
    echo "[$(date)] ERROR: Failed to download helm install script" | tee -a "$LOG_FILE"
    echo "ERROR: Failed to download helm install script" >&2
    exit 1
  fi
  
  echo "[$(date)] helm install script downloaded successfully" | tee -a "$LOG_FILE"
  
  # Run helm install script
  if ! sudo bash get_helm.sh; then
    echo "[$(date)] ERROR: helm installation script failed (exit code: $?)" | tee -a "$LOG_FILE"
    echo "ERROR: helm installation script failed" >&2
    sudo rm -f get_helm.sh
    exit 1
  fi
  
  sudo rm -f get_helm.sh
  
  # Verify installation
  if ! helm version --short > /dev/null 2>&1; then
    echo "[$(date)] ERROR: helm installation verification failed" | tee -a "$LOG_FILE"
    echo "ERROR: helm installation verification failed" >&2
    exit 1
  fi
  
  echo "helm installed: $(helm version --short)"
  echo "[$(date)] helm installed successfully" | tee -a "$LOG_FILE"
else
  echo "helm is already installed: $(helm version --short 2>/dev/null || echo 'version check failed')"
  echo "[$(date)] helm already installed" | tee -a "$LOG_FILE"
fi

echo "[$(date)] base.sh completed successfully" | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"
echo ""
echo "base.sh execution completed successfully"
echo "Log file: $LOG_FILE"

echo "##############################################"
echo "Ready to be added to k8s"
echo "##############################################"
cat  /vagrant/info

# manual test
#sudo mount -t nfs 192.168.86.200:/srv/nfs /mnt
## done

check_host=`cat /etc/hosts | grep 'kube-master'`
if [[ "${check_host}" == "" ]]; then
cat <<EOF >> /etc/hosts
192.168.86.100   kube-master
192.168.86.101   kube-node-1
192.168.86.102   kube-node-2

192.168.86.110   kube-slave-1
192.168.86.112   kube-slave-2
192.168.86.113   kube-slave-3

192.168.86.210   kube-slave-4
192.168.86.212   kube-slave-5
192.168.86.213   kube-slave-6

192.168.86.200   test.default.topzone-k8s.topzone.me consul.default.topzone-k8s.topzone.me vault.default.topzone-k8s.topzone.me
192.168.86.200   consul-server.default.topzone-k8s.topzone.me argocd.default.topzone-k8s.topzone.me
192.168.86.200   jenkins.default.topzone-k8s.topzone.me harbor.harbor.topzone-k8s.topzone.me
192.168.86.200   grafana.default.topzone-k8s.topzone.me prometheus.default.topzone-k8s.topzone.me alertmanager.default.topzone-k8s.topzone.me
192.168.86.200   grafana.default.topzone-k8s.topzone.me prometheus.default.topzone-k8s.topzone.me alertmanager.default.topzone-k8s.topzone.me
192.168.86.200   vagrant-demo-app.devops-dev.topzone-k8s.topzone.me

EOF
fi

