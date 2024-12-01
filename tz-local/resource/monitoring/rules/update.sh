#!/usr/bin/env bash

source /root/.bashrc
function prop { key="${2}=" file="/root/.k8s/${1}" rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); echo "$rslt"; }
cd /topzone/tz-local/resource/monitoring/rules
#bash /topzone/tz-local/resource/monitoring/rules/update.sh

#set -x
shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
admin_password=$(prop 'project' 'admin_password')
basic_password=$(prop 'project' 'basic_password')
STACK_VERSION=44.3.0
#STACK_VERSION=54.0.1
NS=monitoring

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

cp -Rf rule-values.yaml rule-values.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" rule-values.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" rule-values.yaml_bak
helm upgrade --debug --install --reuse-values prometheus prometheus-community/kube-prometheus-stack \
    -n ${NS} \
    --version ${STACK_VERSION} \
    -f rule-values.yaml_bak

kubectl rollout restart statefulset.apps/alertmanager-prometheus-kube-prometheus-alertmanager -n ${NS}

#kubectl rollout restart deployment/prometheus-grafana -n ${NS}
#kubectl rollout restart deployment/prometheus-kube-prometheus-operator -n ${NS}
#kubectl rollout restart deployment/prometheus-kube-state-metrics -n ${NS}
#kubectl rollout restart statefulset.apps/loki -n ${NS}

sleep 120

PROJECTS=(KubeSchedulerDown KubeletTooManyPods TargetDown Watchdog InfoInhibitor KubePodNotReady AlertmanagerClusterFailedToSendAlerts AlertmanagerFailedToSendAlerts KubeDaemonSetRolloutStuck)
for item in "${PROJECTS[@]}"; do
  if [[ "${item}" != "NAME" ]]; then
curl http://alertmanager.default.${k8s_project}.${k8s_domain}/api/v1/silences -d '{
      "matchers": [
        {
          "name": "alertname",
          "value": "'${item}'"
        }
      ],
      "startsAt": "2023-05-05T22:12:33.533330795Z",
      "endsAt": "2053-10-25T23:11:44.603Z",
      "createdBy": "api",
      "comment": "Silence",
      "status": {
        "state": "active"
      }
}'
  fi
done

