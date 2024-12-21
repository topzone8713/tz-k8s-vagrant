#!/usr/bin/env bash

#set -x

##################################################################
# k8s base
##################################################################
export DEBIAN_FRONTEND=noninteractive

if [ -d /vagrant ]; then
  cd /vagrant
fi

sudo groupadd topzone
sudo useradd -g topzone -d /home/topzone -s /bin/bash -m topzone
cat <<EOF > pass.txt
topzone:topzone
EOF
sudo chpasswd < pass.txt
sudo mkdir -p /home/topzone/.ssh &&
  sudo chown -Rf topzone:topzone /home/topzone

MYKEY=tz_rsa
cp -Rf /vagrant/.ssh/${MYKEY} /root/.ssh/${MYKEY}
cp -Rf /vagrant/.ssh/${MYKEY}.pub /root/.ssh/${MYKEY}.pub
touch /home/topzone/.ssh/authorized_keys
cp /home/topzone/.ssh/authorized_keys /root/.ssh/authorized_keys
cat /root/.ssh/${MYKEY}.pub >> /root/.ssh/authorized_keys
chown -R root:root /root/.ssh \
  chmod -Rf 400 /root/.ssh
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
mkdir /srv/nfs
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

192.168.86.111   kube-slave-1
192.168.86.112   kube-slave-2
192.168.86.113   kube-slave-3

192.168.86.211   kube-slave-4
192.168.86.212   kube-slave-5
192.168.86.213   kube-slave-6

192.168.86.200   test.default.topzone-k8s.topzone.me consul.default.topzone-k8s.topzone.me vault.default.topzone-k8s.topzone.me
192.168.86.200   consul-server.default.topzone-k8s.topzone.me argocd.default.topzone-k8s.topzone.me
192.168.86.200   jenkins.default.topzone-k8s.topzone.me harbor.default.topzone-k8s.topzone.me harbor.harbor.topzone-k8s.topzone.me
192.168.86.200   grafana.default.topzone-k8s.topzone.me prometheus.default.topzone-k8s.topzone.me alertmanager.default.topzone-k8s.topzone.me
192.168.86.200   grafana.default.topzone-k8s.topzone.me prometheus.default.topzone-k8s.topzone.me alertmanager.default.topzone-k8s.topzone.me
192.168.86.200   vagrant-demo-app.devops-dev.topzone-k8s.topzone.me

EOF
fi

