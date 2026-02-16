#!/usr/bin/env bash

#https://www.youtube.com/watch?v=3knp2CxmFDI
#https://jerryljh.tistory.com/113
#https://opentelemetry.io/docs/kubernetes/helm/collector/
#https://wlsdn3004.tistory.com/m/43
#https://wlsdn3004.tistory.com/m/47
    #https://medium.com/@dudwls96/kubernetes-%ED%99%98%EA%B2%BD%EC%97%90%EC%84%9C-opentelemetry-collector-%EA%B5%AC%EC%84%B1%ED%95%98%EA%B8%B0-d20e474a8b18
#https://www.elastic.co/kr/blog/implementing-kubernetes-observability-security-opentelemetry

source /root/.bashrc
#bash /vagrant/tz-local/resource/opentelemetry/install.sh
cd /vagrant/tz-local/resource/opentelemetry

#set -x
shopt -s expand_aliases

k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
minio_access_key_id=$(prop 'project' 'minio_access_key_id')
minio_secret_access_key=$(prop 'project' 'minio_secret_access_key')
dockerhub_id=$(prop 'project' 'dockerhub_id')
dockerhub_password=$(prop 'project' 'dockerhub_password')

NS=opentelemetry-operator
alias k='kubectl --kubeconfig ~/.kube/config -n '${NS}

#kubectl delete ns ${NS}
kubectl create ns ${NS}

#1. Cert-Manager 설치
#2. k8s Open Telemetry Operator 설치
#cp opentelemetry-operator_values.yaml opentelemetry-operator_values.yaml_bak
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
#helm show values open-telemetry/opentelemetry-operator > opentelemetry-operator_values.yaml
#helm uninstall opentelemetry-operator -n ${NS}
#--reuse-values
helm upgrade --debug --install --reuse-values \
  opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace ${NS} \
  --create-namespace \
  --values "opentelemetry-operator_values_bak.yaml" \
  --version 0.29.2 \
  --set admissionWebhooks.certManager.enabled=false \
  --set admissionWebhooks.certManager.autoGenerateCert=true

#3. Grafana Tempo 설치
#kubectl delete ns tempo
kubectl create ns tempo
#helm show values grafana/tempo-distributed > tempo_values.yaml
#helm delete tempo -n tempo

cp tempo_values.yaml tempo_values.yaml_bak
sed -ie "s|minio_access_key_id|${minio_access_key_id}|g" tempo_values.yaml_bak
sed -ie "s|minio_secret_access_key|${minio_secret_access_key}|g" tempo_values.yaml_bak

#helm uninstall tempo -n tempo
#--reuse-values
helm upgrade --debug --install --reuse-values \
  tempo grafana/tempo-distributed \
  --create-namespace \
  --namespace tempo \
  --values "tempo_values.yaml_bak" \
  --version 1.4.2

# add Data Sources / Tempo in grafana datasource
#kubectl get svc tempo-distributor-discovery -n tempo
#NAME                          TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                                AGE
#tempo-distributor-discovery   ClusterIP   None         <none>        3100/TCP,4318/TCP,4317/TCP,55680/TCP   9m9s
# https://grafana.topzone.me/datasources/edit/tempo
#URL: http://tempo-query-frontend-discovery.tempo:3100

#4. Open Telemetry Collector + Auto Instrumentation 설치 (Only when opentelemetry-collector is deployment)
# install opentelemetry-collector
#helm show values open-telemetry/opentelemetry-collector > opentelemetry-collector_values.yaml
#helm uninstall opentelemetry-collector -n ${NS}
helm upgrade --debug --install --reuse-values \
  opentelemetry-collector open-telemetry/opentelemetry-collector \
  --set image.repository=otel/opentelemetry-collector \
  --values "opentelemetry-collector_values.yaml" \
  --namespace ${NS}

# Auto Instrumentation 설치 (Only when opentelemetry-collector is deployment)
#kubectl delete ns nlp
kubectl create ns nlp
kubectl delete -f opentelemetry-instrumentation.yaml -n nlp
kubectl apply -f opentelemetry-instrumentation.yaml -n nlp

kubectl get instrumentations.opentelemetry.io -n nlp
#NAME                            AGE   ENDPOINT                                                     SAMPLER                    SAMPLER ARG
#opentelemetry-instrumentation   14m   http://opentelemetry-collector.opentelemetry-operator:4317   parentbased_traceidratio   1

#kubectl delete -f opentelemetry-operator.yaml -n opentelemetry-operator
#kubectl apply -f opentelemetry-operator.yaml -n opentelemetry-operator
#kubectl get endpoints --namespace opentelemetry-operator opentelemetry-operator-webhook

#You will need to either add a firewall rule that allows master nodes access to port 9443/tcp on worker nodes,
# or change the existing rule that allows access to
# port 80/tcp, 443/tcp and 10254/tcp to also allow access to port 9443/tcp.

# Build and deploy otel-test-app (Node.js app for OpenTelemetry testing)
docker build --platform linux/amd64 -t otel-test-app:latest ./otel-test-app
docker tag otel-test-app:latest ${dockerhub_id}/otel-test-app:latest
echo "${dockerhub_password}" | docker login -u ${dockerhub_id} --password-stdin docker.io
docker push ${dockerhub_id}/otel-test-app:latest
sed -i.bak "s|image: .*otel-test-app.*|image: ${dockerhub_id}/otel-test-app:latest|g" otel-test-app.yaml
kubectl delete -f otel-test-app.yaml -n nlp 2>/dev/null || true
kubectl apply -f otel-test-app.yaml -n nlp
kubectl describe otelinst -n nlp
kubectl logs -l app.kubernetes.io/name=opentelemetry-operator \
  --container manager -n opentelemetry-operator --follow

PROJECTS=(devops devops-dev)
for item in "${PROJECTS[@]}"; do
  echo "===================== ${item}"
  kubectl delete -f opentelemetry-instrumentation.yaml -n ${item}
  kubectl apply -f opentelemetry-instrumentation.yaml -n ${item}
done

kubectl -n ${NS} apply -f collector-ingress.yaml

curl -i http://opentelemetry.topzone.me/v1/traces -X POST -H "Content-Type: application/json" -d @span.json

exit 0

#git clone https://github.com/grafana/tns.git
#cd tns/production/k8s-yamls

kubectl create ns tns
kubectl apply -f tns/k8s-yamls -n tempo

helm repo add grafana https://grafana.github.io/helm-charts
kubectl create ns tempo
helm install tempo grafana/tempo -n tempo
#helm install grafana grafana/grafana -n tempo

URL: http://tempo.tempo:3100


## python

curl -i http://opentelemetry.topzone.me/v1/traces -X POST -H "Content-Type: application/json" -d @span.json

from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

resource = Resource(attributes={
    SERVICE_NAME: "tz-devops-admin"
})

traceProvider = TracerProvider(resource=resource)
processor = BatchSpanProcessor(OTLPSpanExporter(endpoint="http://opentelemetry.topzone.me/v1/traces"))
traceProvider.add_span_processor(processor)
trace.set_tracer_provider(traceProvider)

    def do_GET(self, httpd):
        tracer = trace.get_tracer("do_GET")
        with self.tracer.start_as_current_span("ri_cal") as span:
            span.set_attribute("printed_string", "done")
            with self.tracer.start_as_current_span("ri_usage") as span:
                span.set_attribute("printed_string", "done")

https://grafana.topzone.me/explore?orgId=1&left=%7B%22datasource%22:%22tempo%22,%22queries%22:%5B%7B%22refId%22:%22A%22,%22datasource%22:%7B%22type%22:%22tempo%22,%22uid%22:%22tempo%22%7D,%22queryType%22:%22nativeSearch%22,%22serviceName%22:%22tz-devops-admin%22,%22spanName%22:%22%2Fawsri%3Fprofile%3Dtz-596627550572%26region%3Dap-northeast-2%26type%3Ddb%22%7D%5D,%22range%22:%7B%22from%22:%22now-5m%22,%22to%22:%22now%22%7D%7D&right=%7B%22datasource%22:%22tempo%22,%22queries%22:%5B%7B%22query%22:%2261becbb1231ad192eba20ecef87d0e3d%22,%22queryType%22:%22traceId%22,%22refId%22:%22A%22%7D%5D,%22range%22:%7B%22from%22:%221713497073313%22,%22to%22:%221713497373313%22%7D%7D


# node.js
/Volumes/workspace/sl/hypen_edu_server/package.json
  "dependencies": {
    "@opentelemetry/api": "^1.7.0",
    "@opentelemetry/auto-instrumentations-node": "^0.40.0"

apiVersion: apps/v1
kind: Deployment
metadata:
  name: hypen-hypen-edu-server-devops
spec:
  selector:
    matchLabels:
      app: hypen-hypen-edu-server-devops
  template:
    metadata:
      annotations:
        instrumentation.opentelemetry.io/inject-nodejs: "true"
