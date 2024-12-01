#!/usr/bin/env bash

export PROJECT_BASE='/topzone/'

cd /topzone

sudo mkdir -p /home/topzone/.k8s
sudo cp -Rf /topzone/resources/${k8s_project}/project /home/topzone/.k8s/project
sudo chown -Rf topzone:topzone /home/topzone/.k8s
sudo rm -Rf /root/.k8s
sudo cp -Rf /home/topzone/.k8s /root/.k8s

sudo mkdir -p /home/topzone/.kube
sudo cp -Rf /topzone/resources/${k8s_project}/kubeconfig_${k8s_project} /home/topzone/.kube/config
sudo chown -Rf topzone:topzone /home/topzone/.kube
sudo rm -Rf /root/.kube
sudo cp -Rf /home/topzone/.kube /root/.kube

git config --global --add safe.directory '*'

#echo "118.33.104.1     shoptoolstest.co.kr topzone1.iptime.org topzone2.iptime.org kubernetes.default.svc.cluster.local" >> /etc/hosts

#echo "192.168.0.27    test.vault.home-k8s.shoptoolstest.co.kr consul.default.home-k8s.shoptoolstest.co.kr vault.default.home-k8s.shoptoolstest.co.kr vault2.default.home-k8s.shoptoolstest.co.kr argocd.default.home-k8s.shoptoolstest.co.kr jenkins.default.home-k8s.shoptoolstest.co.kr" >> /etc/hosts
#echo "192.168.0.36    test.vault.home-k8s.shoptoolstest.co.kr consul.default.home-k8s.shoptoolstest.co.kr vault.default.home-k8s.shoptoolstest.co.kr vault2.default.home-k8s.shoptoolstest.co.kr argocd.default.home-k8s.shoptoolstest.co.kr jenkins.default.home-k8s.shoptoolstest.co.kr" >> /etc/hosts

exit 0
