#!/usr/bin/env bash

export PROJECT_BASE='/vagrant/'

cd /vagrant

sudo mkdir -p /home/topzone/.k8s
sudo cp -Rf /vagrant/resources/project /home/topzone/.k8s/project
sudo chown -Rf topzone:topzone /home/topzone/.k8s
sudo rm -Rf /root/.k8s
sudo cp -Rf /home/topzone/.k8s /root/.k8s

sudo mkdir -p /home/topzone/.kube
sudo cp -Rf /vagrant/resources/kubeconfig_${k8s_project} /home/topzone/.kube/config
sudo chown -Rf topzone:topzone /home/topzone/.kube
sudo rm -Rf /root/.kube
sudo cp -Rf /home/topzone/.kube /root/.kube

git config --global --add safe.directory '*'

exit 0
