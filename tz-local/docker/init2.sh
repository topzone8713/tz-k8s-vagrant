#!/usr/bin/env bash

export PROJECT_BASE='/vagrant/'

cd /vagrant

sudo mkdir -p /home/vagrant/.aws
sudo cp -Rf /vagrant/resources/${k8s_project}/project /home/vagrant/.aws/project
sudo chown -Rf vagrant:vagrant /home/vagrant/.aws
sudo rm -Rf /root/.aws
sudo cp -Rf /home/vagrant/.aws /root/.aws

sudo mkdir -p /home/vagrant/.kube
sudo cp -Rf /vagrant/resources/${k8s_project}/kubeconfig_${k8s_project} /home/vagrant/.kube/config
sudo chown -Rf vagrant:vagrant /home/vagrant/.kube
sudo rm -Rf /root/.kube
sudo cp -Rf /home/vagrant/.kube /root/.kube

git config --global --add safe.directory '*'

#echo "118.33.104.1     shoptoolstest.co.kr topzone1.iptime.org topzone2.iptime.org kubernetes.default.svc.cluster.local" >> /etc/hosts

#echo "192.168.0.27    test.vault.home-k8s.shoptoolstest.co.kr consul.default.home-k8s.shoptoolstest.co.kr vault.default.home-k8s.shoptoolstest.co.kr vault2.default.home-k8s.shoptoolstest.co.kr argocd.default.home-k8s.shoptoolstest.co.kr jenkins.default.home-k8s.shoptoolstest.co.kr" >> /etc/hosts
#echo "192.168.0.36    test.vault.home-k8s.shoptoolstest.co.kr consul.default.home-k8s.shoptoolstest.co.kr vault.default.home-k8s.shoptoolstest.co.kr vault2.default.home-k8s.shoptoolstest.co.kr argocd.default.home-k8s.shoptoolstest.co.kr jenkins.default.home-k8s.shoptoolstest.co.kr" >> /etc/hosts

exit 0
