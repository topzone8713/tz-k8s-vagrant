#!/usr/bin/env bash

# alert
#https://nws.netways.de/tutorials/2020/10/07/kubernetes-alerting-with-prometheus-alert-manager/
#https://dev.to/cosckoya/prometheus-alertmanager-with-sendgrid-and-slack-api-4f8a
#https://grafana.com/docs/grafana/latest/datasources/cloudwatch/
#https://prometheus.io/docs/instrumenting/exporters/#http

source /root/.bashrc
function prop { key="${2}=" file="/root/.k8s/${1}" rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); rslt=$(echo "$rslt" | tr -d '\n' | tr -d '\r'); echo "$rslt"; }
#bash /vagrant/tz-local/resource/monitoring/install.sh
cd /vagrant/tz-local/resource/monitoring

#set -x
shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
admin_password=$(prop 'project' 'admin_password')
basic_password=$(prop 'project' 'basic_password')
grafana_goauth2_client_id=$(prop 'project' 'grafana_goauth2_client_id')
grafana_goauth2_client_secret=$(prop 'project' 'grafana_goauth2_client_secret')
smtp_password=$(prop 'project' 'smtp_password')
STACK_VERSION=44.3.0
#STACK_VERSION=54.0.1
NS=monitoring

#helm repo add grafana https://grafana.github.io/helm-charts
#helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
#helm show chart prometheus-community/kube-prometheus-stack

#k delete ns ${NS}
k create ns ${NS}
#helm inspect values prometheus-community/kube-prometheus-stack > kube-prometheus-stack-values.yaml

#kubectl -n ${NS} delete -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.45.0/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml && \
#kubectl -n ${NS} delete -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.45.0/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml && \
#kubectl -n ${NS} delete -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.45.0/example/prometheus-operator-crd/monitoring.coreos.com_probes.yaml && \
#kubectl -n ${NS} delete -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.45.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml && \
#kubectl -n ${NS} delete -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.45.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml && \
#kubectl -n ${NS} delete -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.45.0/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml && \
#kubectl -n ${NS} delete -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.45.0/example/prometheus-operator-crd/monitoring.coreos.com_thanosrulers.yaml

cp -Rf values.yaml values.yaml_bak
sed -i "s/admin_password/${admin_password}/g" values.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" values.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" values.yaml_bak
sed -i "s/smtp_password/${smtp_password}/g" values.yaml_bak
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
#helm repo add kube-state-metrics https://kubernetes.github.io/kube-state-metrics
#helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
#helm search repo prometheus-community
#helm search repo kube-state-metrics
#helm uninstall prometheus -n ${NS}
#helm fetch --untar prometheus-community/kube-prometheus-stack
#--reuse-values
helm upgrade --debug --install prometheus prometheus-community/kube-prometheus-stack \
    -n ${NS} \
    --version ${STACK_VERSION} \
    --set alertmanager.persistentVolume.storageClass="nfs-client" \
    --set server.persistentVolume.storageClass="nfs-client"
#--reuse-values
helm upgrade --debug --install --reuse-values prometheus prometheus-community/kube-prometheus-stack \
    -n ${NS} \
    --version ${STACK_VERSION} \
    -f values.yaml_bak \
    --set alertmanager.baseURL=http://alertmanager.default.${k8s_project}.${k8s_domain}

#k patch deployment/prometheus-kube-state-metrics -p '{"spec": {"template": {"spec": {"nodeSelector": {"team": "devops"}}}}}' -n ${NS}
#k patch deployment/prometheus-kube-state-metrics -p '{"spec": {"template": {"spec": {"nodeSelector": {"environment": "monitoring"}}}}}' -n ${NS}
k patch deployment/prometheus-kube-state-metrics -p '{"spec": {"template": {"spec": {"imagePullSecrets": [{"name": "tz-registrykey"}]}}}}' -n ${NS}

helm uninstall tz-blackbox-exporter -n ${NS}
#--reuse-values
helm upgrade --debug --install -n ${NS} tz-blackbox-exporter prometheus-community/prometheus-blackbox-exporter
#  --set nodeSelector.team=devops \
#  --set nodeSelector.environment=${NS}

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
#helm search repo loki
helm uninstall loki -n ${NS}

sed -i "s/k8s_project/${k8s_project}/g" values.yaml_bak
#helm show chart grafana/loki-stack
#--reuse-values
#2.9.9
helm upgrade --install loki grafana/loki-stack --version 2.9.11 \
  -n ${NS} \
  --set persistence.enabled=true,persistence.type=pvc,persistence.size=10Gi
#k patch statefulset/loki -p '{"spec": {"template": {"spec": {"nodeSelector": {"team": "devops"}}}}}' -n ${NS}
#k patch statefulset/loki -p '{"spec": {"template": {"spec": {"nodeSelector": {"environment": "monitoring"}}}}}' -n ${NS}
k patch statefulset/loki -p '{"spec": {"template": {"spec": {"imagePullSecrets": [{"name": "tz-registrykey"}]}}}}' -n ${NS}

k patch daemonset/loki-promtail -p '{"spec": {"template": {"spec": {"imagePullSecrets": [{"name": "tz-registrykey"}]}}}}' -n ${NS}
# loki datasource: http://loki.monitoring.svc.cluster.local:3100/

bash s3.sh

cp -Rf configmap.yaml configmap.yaml_bak
sed -i "s/admin_password/${admin_password}/g" configmap.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" configmap.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" configmap.yaml_bak
sed -i "s/grafana_goauth2_client_id/${grafana_goauth2_client_id}/g" configmap.yaml_bak
sed -i "s/grafana_goauth2_client_secret/${grafana_goauth2_client_secret}/g" configmap.yaml_bak
sed -i "s/smtp_password/${smtp_password}/g" configmap.yaml_bak
k -n ${NS} apply -f configmap.yaml_bak
#curl -X POST http://prometheus.default.${k8s_project}.${k8s_domain}/-/reload

#curl https://grafana.default.${k8s_project}.${k8s_domain}
#admin / prom-operator
#grafana_pod=$(kubectl -n ${NS} get pod | grep prometheus-grafana | awk '{print $1}')
#kubectl exec -it ${grafana_pod} \
#  -n ${NS} -c grafana grafana-cli admin reset-admin-password ${admin_password}
#kubectl get csr -o name | xargs kubectl certificate approve

# basic auth
#https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/
#https://kubernetes.github.io/ingress-nginx/examples/auth/basic/
#echo ${basic_password} | htpasswd -i -n admin > auth
#k delete secret basic-auth-grafana -n ${NS}
#k create secret generic basic-auth-grafana --from-file=auth -n ${NS}
#k get secret basic-auth-grafana -o yaml -n ${NS}
cp -Rf grafana-ingress.yaml grafana-ingress.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" grafana-ingress.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" grafana-ingress.yaml_bak
k delete -f grafana-ingress.yaml_bak -n ${NS}
k apply -f grafana-ingress.yaml_bak -n ${NS}

kubectl rollout restart deployment/prometheus-grafana -n ${NS}
kubectl rollout restart deployment/prometheus-kube-prometheus-operator -n ${NS}
kubectl rollout restart deployment/prometheus-kube-state-metrics -n ${NS}
kubectl rollout restart statefulset.apps/loki -n ${NS}

cp alertmanager-values.yaml alertmanager-values.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" alertmanager-values.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" alertmanager-values.yaml_bak
sed -i "s/admin_password/${admin_password}/g" alertmanager-values.yaml_bak
sed -i "s/smtp_password/${smtp_password}/g" alertmanager-values.yaml_bak

alertmanager=$(cat alertmanager-values.yaml_bak | base64 -w0)
cp alertmanager-secret-k8s.yaml alertmanager-secret-k8s.yaml_bak
sed -i "s|ALERTMANAGER_ENCODE|${alertmanager}|g" alertmanager-secret-k8s.yaml_bak
kubectl -n ${NS} apply -f alertmanager-secret-k8s.yaml_bak
kubectl rollout restart statefulset.apps/alertmanager-prometheus-kube-prometheus-alertmanager -n ${NS}

k get pv | grep prometheus

# Prometheus
#k -n ${NS} port-forward svc/prometheus-kube-prometheus-prometheus 9090
#k -n ${NS} port-forward svc/prometheus-grafana 3000:80
#k -n ${NS} port-forward svc/loki 3100:3100
#POD_NAME=$(k -n ${NS} get pods --namespace prometheus -l "app=prometheus,component=alertmanager" -o jsonpath="{.items[0].metadata.name}")
#k -n ${NS} port-forward $POD_NAME 9093

#echo ${basic_password} | htpasswd -i -n admin > auth
#k delete secret basic-auth-prometheus -n ${NS}
#k create secret generic basic-auth-prometheus --from-file=auth -n ${NS}
#k get secret basic-auth-prometheus -o yaml -n ${NS}
cp -Rf prometheus-ingress.yaml prometheus-ingress.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" prometheus-ingress.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" prometheus-ingress.yaml_bak
k delete -f prometheus-ingress.yaml_bak -n ${NS}
k apply -f prometheus-ingress.yaml_bak -n ${NS}

#echo ${basic_password} | htpasswd -i -n admin > auth
#k delete secret basic-auth-alertmanager -n ${NS}
#k create secret generic basic-auth-alertmanager --from-file=auth -n ${NS}
#k get secret basic-auth-alertmanager -o yaml -n ${NS}
cp -Rf alertmanager-ingress.yaml alertmanager-ingress.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" alertmanager-ingress.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" alertmanager-ingress.yaml_bak
k delete -f alertmanager-ingress.yaml_bak -n ${NS}
k apply -f alertmanager-ingress.yaml_bak -n ${NS}

rm -Rf auth
kubectl get certificate -n ${NS}
kubectl describe certificate ingress-grafana-tls -n ${NS}

kubectl get secrets --all-namespaces | grep ingress-grafana-tls
kubectl get certificates --all-namespaces | grep ingress-grafana-tls

sleep 60
grafana_pod=$(kubectl -n ${NS} get pod | grep prometheus-grafana | awk '{print $1}')
kubectl exec -it ${grafana_pod} -n ${NS} \
   -c grafana grafana-cli plugins install grafana-piechart-panel

#helm repo add influxdata https://helm.influxdata.com/
#helm install influxdb influxdata/influxdb -n ${NS}
#k patch statefulset/influxdb -p '{"spec": {"template": {"spec": {"nodeSelector": {"team": "devops"}}}}}' -n ${NS}
#k patch statefulset/influxdb -p '{"spec": {"template": {"spec": {"nodeSelector": {"environment": "monitoring"}}}}}' -n ${NS}
#k patch statefulset/influxdb -p '{"spec": {"template": {"spec": {"imagePullSecrets": [{"name": "tz-registrykey"}]}}}}' -n ${NS}

kubectl patch statefulset/alertmanager-prometheus-kube-prometheus-alertmanager -p '{"spec": {"template": {"spec": {"imagePullSecrets": [{"name": "tz-registrykey"}]}}}}' -n ${NS}

cp -Rf /vagrant/tz-local/resource/monitoring/backup/grafanaSettings.json /vagrant/tz-local/resource/monitoring/backup/grafanaSettings.json_bak
sed -i "s/k8s_project/${k8s_project}/g" /vagrant/tz-local/resource/monitoring/backup/grafanaSettings.json_bak
sed -i "s/k8s_domain/${k8s_domain}/g" /vagrant/tz-local/resource/monitoring/backup/grafanaSettings.json_bak
sed -i "s/admin_password_var/${admin_password}/g" /vagrant/tz-local/resource/monitoring/backup/grafanaSettings.json_bak

grafana_token_var=$(curl -X POST -H "Content-Type: application/json" -d '{"name":"admin-key", "role": "Admin"}' "http://admin:${admin_password}@grafana.default.${k8s_project}.${k8s_domain}/api/auth/keys" | jq -r '.key')
echo ${grafana_token_var} #
sleep 5
if [[ "${grafana_token_var}" != "" ]]; then
  sed -i "s/grafana_token_var/${grafana_token_var}/g" /vagrant/tz-local/resource/monitoring/backup/grafanaSettings.json_bak
fi

#helm repo add fluent https://fluent.github.io/helm-charts
#helm repo update
#helm install fluentd fluent/fluentd --version 0.3.9 \
#  -n ${NS} -f values.yaml_bak
#
#fluentd_vaules.yaml

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

exit 0

1. aws datasource setting
  Data Sources / CloudWatch: https://grafana.default.${k8s_project}.${k8s_domain}/datasources/edit/2/
  #  Assess and secret key for "grafana" user
  #  Attach existing policies directly
  #CloudWatchReadOnlyAccess
  #AmazonEC2ReadOnlyAccess

2. import charts
https://grafana.com/grafana/dashboards/707
rds: 707
loki: 12019
k8s-storage-volumes-cluster: 11454
k8s: 13770
loki app/log: 13639


################################################################################
# custom prometheus alert
# https://lapee79.github.io/article/monitoring-http-using-blackbox-exporter/
################################################################################
#kubectl -n monitoring get prometheusrules prometheus-kube-prometheus-alertmanager.rules -o yaml > prometheus-kube-prometheus-alertmanager.rules.yaml
kubectl -n monitoring apply -f prometheus-kube-prometheus-alertmanager.rules.yaml




helm repo add deliveryhero https://charts.deliveryhero.io/
helm repo update
helm install my-release deliveryhero/k8s-event-logger -f values.yaml


sa
prometheus-kube-prometheus-prometheus
binding
prometheus-kube-prometheus-prometheus


http://alertmanager.default.${k8s_project}.${k8s_domain}/#/alerts

#          "value": "Watchdog",
#          "isRegex": true

