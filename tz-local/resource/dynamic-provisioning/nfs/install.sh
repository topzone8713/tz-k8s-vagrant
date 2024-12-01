#!/usr/bin/env bash

source /root/.bashrc
cd /topzone/tz-local/resource/dynamic-provisioning/nfs

shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

# install NFS in k8s
#https://github.com/kubernetes-csi/csi-driver-nfs/blob/master/deploy/example/nfs-provisioner/README.md

apt update
apt install -y nfs-server nfs-common
mkdir /srv/nfs
sudo chown nobody:nogroup /srv/nfs
sudo chmod 0777 /srv/nfs
cat << EOF >> /etc/exports
/srv/nfs 192.168.0.0/24(rw,no_subtree_check,no_root_squash)
EOF
systemctl enable --now nfs-server
exportfs -ar

helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --create-namespace \
  --namespace nfs-provisioner \
  --set nfs.server=192.168.86.90 \
  --set nfs.path=/srv/nfs

## 1. Install NFS CSI driver master version on a kubernetes cluster
#curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/install-driver.sh | bash -s master --
#k -n kube-system get pod -o wide -l app=csi-nfs-controller
#k -n kube-system get pod -o wide -l app=csi-nfs-node

## 3. Verifying a driver installation
#k get csinodes \
#-o jsonpath='{range .items[*]} {.metadata.name}{": "} {range .spec.drivers[*]} {.name}{"\n"} {end}{end}'

#k create -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/example/nfs-provisioner/nginx-pod.yaml
#k exec nginx-nfs-example -n default -- bash -c "findmnt /var/www -o TARGET,SOURCE,FSTYPE"
#k delete -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/example/nfs-provisioner/nginx-pod.yaml

cd /topzone/tz-local/resource/dynamic-provisioning/nfs
###############################################################
# !!! Storage Class Usage (Dynamic Provisioning)
###############################################################
k delete -f dynamic-provisioning-nfs.yaml
k apply -f dynamic-provisioning-nfs.yaml
k apply -f dynamic-provisioning-nfs-test.yaml
k get pv,pvc
k delete -f dynamic-provisioning-nfs-test.yaml

###############################################################
# !!! PV/PVC Usage (Static Provisioning)
###############################################################
k delete -f static-provisioning-nfs.yaml
k apply -f static-provisioning-nfs.yaml
k apply -f static-provisioning-nfs-test.yaml
k get pv,pvc
k delete -f static-provisioning-nfs-test.yaml

exit 0