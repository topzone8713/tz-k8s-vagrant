#!/usr/bin/env bash

function prop { key="${2}=" file="/root/.k8s/${1}" rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); rslt=$(echo "$rslt" | tr -d '\n' | tr -d '\r'); echo "$rslt"; }

k8s_project=$(prop 'project' 'project')

bash /vagrant/tz-local/resource/vault/data/vault_user.sh
bash /vagrant/tz-local/resource/vault/vault-injection/install.sh
bash /vagrant/tz-local/resource/vault/vault-injection/update.sh
bash /vagrant/tz-local/resource/vault/external-secrets/install.sh
bash /vagrant/tz-local/resource/vault/external-secrets/install_vault.sh

bash /vagrant/tz-local/resource/monitoring/install.sh
bash /vagrant/tz-local/resource/monitoring/rules/update.sh

bash /vagrant/tz-local/resource/harbor/install.sh

bash /vagrant/tz-local/resource/argocd/helm/install.sh
bash /vagrant/tz-local/resource/jenkins/helm/install.sh

exit 0
