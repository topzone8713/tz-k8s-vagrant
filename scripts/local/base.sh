#!/usr/bin/env bash

#set -x

##################################################################
# k8s base
##################################################################

if [ -d /topzone ]; then
  cd /topzone
fi

MYKEY=tz_rsa
cp -Rf /vagrant/.ssh/${MYKEY} /root/.ssh/${MYKEY}
cp -Rf /vagrant/.ssh/${MYKEY}.pub /root/.ssh/${MYKEY}.pub
cp /home/vagrant/.ssh/authorized_keys /root/.ssh/authorized_keys
cat /root/.ssh/${MYKEY}.pub >> /root/.ssh/authorized_keys
chown -R root:root /root/.ssh \
  chmod -Rf 400 /root/.ssh
rm -Rf /home/vagrant/.ssh \
  && cp -Rf /root/.ssh /home/vagrant/.ssh \
  && chown -Rf topzone:topzone /home/vagrant/.ssh \
  && chmod -Rf 700 /home/vagrant/.ssh \
  && chmod -Rf 600 /home/vagrant/.ssh/*

cat <<EOF >> /etc/resolv.conf
nameserver 1.1.1.1 #cloudflare DNS
nameserver 8.8.8.8 #Google DNS
EOF

sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
#sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo apt-get update
sudo apt install -y python3 python3-pip net-tools git

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

sudo groupadd topzone
sudo useradd -g topzone -d /home/topzone -s /bin/bash -m topzone
cat <<EOF > pass.txt
topzone:topzone
EOF
sudo chpasswd < pass.txt

cat <<EOF >> /etc/hosts
192.168.86.100   kube-master
192.168.86.101   kube-node-1
192.168.86.102   kube-node-2

192.168.86.97   kube-slave-1
192.168.86.98   kube-slave-2
192.168.86.99   kube-slave-3

192.168.86.94   kube-slave-4
192.168.86.95   kube-slave-5
192.168.86.99   kube-slave-6
EOF
