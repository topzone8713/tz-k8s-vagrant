#!/usr/bin/env bash

source /root/.bashrc
cd /vagrant/tz-local/resource/jenkins/helm

#set -x
shopt -s expand_aliases
alias k='kubectl --kubeconfig ~/.kube/config'

k8s_project=hyper-k8s  #$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')

helm repo add jenkins https://charts.jenkins.io
helm search repo jenkins

helm list --all-namespaces -a
k delete namespace jenkins
k create namespace jenkins
k apply -f jenkins.yaml

cp -Rf values.yaml values.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" values.yaml_bak

helm delete jenkins -n jenkins
#--reuse-values
helm upgrade --debug --install jenkins jenkins/jenkins  -f values.yaml_bak -n jenkins
#k patch svc jenkins --type='json' -p '[{"op":"replace","path":"/spec/type","value":"NodePort"},{"op":"replace","path":"/spec/ports/0/nodePort","value":31000}]' -n jenkins
#k patch svc jenkins -p '{"spec": {"ports": [{"port": 8080,"targetPort": 8080, "name": "http"}], "type": "ClusterIP"}}' -n jenkins --force

cp -Rf jenkins-ingress.yaml jenkins-ingress.yaml_bak
sed -i "s/k8s_project/${k8s_project}/g" jenkins-ingress.yaml_bak
sed -i "s/k8s_domain/${k8s_domain}/g" jenkins-ingress.yaml_bak
k apply -f jenkins-ingress.yaml_bak -n jenkins

echo "waiting for starting a jenkins server!"
sleep 60

#--profile ${k8s_project}
#
#aws ecr get-login-password --region ${AWS_REGION} \
#      | docker login --username AWS --password-stdin ${aws_account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com

mkdir -p /root/.docker
#echo "{\"credHelpers\":{\"$ECR_REGISTRY\":\"ecr-login\"}}" > /root/.docker/config2.json
kubectl -n jenkins delete configmap docker-config
kubectl -n jenkins create configmap docker-config --from-file=/root/.docker/config.json

kubectl -n jenkins delete secret aws-secret
kubectl -n jenkins create secret generic aws-secret \
  --from-file=/root/.aws/credentials

echo "
##[ Jenkins ]##########################################################
#  - URL: http://jenkins.default.${k8s_project}.${k8s_domain}
#
#  - ID: admin
#  - Password:
#    kubectl -n jenkins exec -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/chart-admin-password && echo
#######################################################################
" >> /vagrant/info
cat /vagrant/info

exit 0

