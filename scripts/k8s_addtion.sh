#!/usr/bin/env bash

function prop {
	grep "${2}" "/home/vagrant/.aws/${1}" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'
}
k8s_project=hyper-k8s  #$(prop 'project' 'project')

bash /vagrant/tz-local/resource/docker-repo/install.sh
bash /vagrant/tz-local/resource/ingress_nginx/install.sh

bash /vagrant/tz-local/resource/consul/install.sh
bash /vagrant/tz-local/resource/vault/helm/install.sh
bash /vagrant/tz-local/resource/vault/data/vault_user.sh
bash /vagrant/tz-local/resource/vault/vault-injection/install.sh
bash /vagrant/tz-local/resource/vault/vault-injection/update.sh
bash /vagrant/tz-local/resource/vault/external-secrets/install_vault.sh

bash /vagrant/tz-local/resource/argocd/helm/install.sh
bash /vagrant/tz-local/resource/jenkins/helm/install.sh

bash /vagrant/tz-local/resource/monitoring/install.sh

exit 0

bash /vagrant/tz-local/resource/vault/external-secrets/install.sh
