#!/usr/bin/env bash

function prop {
	grep "${2}" "/home/topzone/.k8s/${1}" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'
}
k8s_project=hyper-k8s  #$(prop 'project' 'project')

bash /topzone/tz-local/resource/docker-repo/install.sh
bash /topzone/tz-local/resource/ingress_nginx/install.sh

bash /topzone/tz-local/resource/consul/install.sh
bash /topzone/tz-local/resource/vault/helm/install.sh
bash /topzone/tz-local/resource/vault/data/vault_user.sh
bash /topzone/tz-local/resource/vault/vault-injection/install.sh
bash /topzone/tz-local/resource/vault/vault-injection/update.sh
bash /topzone/tz-local/resource/vault/external-secrets/install_vault.sh

bash /topzone/tz-local/resource/argocd/helm/install.sh
bash /topzone/tz-local/resource/jenkins/helm/install.sh

bash /topzone/tz-local/resource/monitoring/install.sh

exit 0

bash /topzone/tz-local/resource/vault/external-secrets/install.sh
