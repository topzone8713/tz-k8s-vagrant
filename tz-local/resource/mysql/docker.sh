#https://aws.amazon.com/ko/premiumsupport/knowledge-center/eks-persistent-storage/

cd /vagrant/tz-local/resource/mysql

aws_access_key_id=$(prop 'credentials' 'aws_access_key_id')
aws_secret_access_key=$(prop 'credentials' 'aws_secret_access_key')
AWS_REGION=$(prop 'config' 'region')
k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
VAULT_TOKEN=$(prop 'project' 'vault')
dockerhub_id=$(prop 'project' 'dockerhub_id')
dockerhub_password=$(prop 'project' 'dockerhub_password')
docker_url=$(prop 'project' 'docker_url')

aws_account_id=$(aws sts get-caller-identity --query Account --output text)
NS=devops-dev

sudo apt-get -y install docker.io
sudo usermod -G docker topzone
sudo chown -Rf topzone:topzone /var/run/docker.sock

SNAPSHOT_IMG=tz-mysql-snapshot
TAG=11

aws ecr create-repository \
    --repository-name $SNAPSHOT_IMG \
    --image-tag-mutability IMMUTABLE

#docker login --username AWS -p $(aws ecr get-login-password --region ${AWS_REGION}) ${aws_account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com/
echo $dockerhub_password | docker login -u $dockerhub_id --password-stdin ${docker_url}
DOCKER_ID=${aws_account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com

docker image build -t ${SNAPSHOT_IMG} .
docker tag ${SNAPSHOT_IMG}:latest ${DOCKER_ID}/${SNAPSHOT_IMG}:${TAG}
docker push ${DOCKER_ID}/${SNAPSHOT_IMG}:${TAG}

export VAULT_ADDR="http://vault.default.${k8s_project}.${k8s_domain}"
echo $VAULT_ADDR
vault login ${VAULT_TOKEN}

vault kv put secret/devops-prod/aws \
  AWS_ACCESS_KEY_ID=${aws_access_key_id} \
  AWS_SECRET_ACCESS_KEY=${aws_secret_access_key} \
  AWS_DEFAULT_REGION=${AWS_REGION}

#docker run tz-mysql-snapshot vol-0ccc1a959af735003
#docker exec -it 48cdd1ac2e73 sh

cp tz-mysql_cronJob.yaml tz-mysql_cronJob.yaml_bak
sed -i "s/aws_account_id/${aws_account_id}/g" tz-mysql_cronJob.yaml_bak
sed -i "s/AWS_REGION/${AWS_REGION}/g" tz-mysql_cronJob.yaml_bak
k delete -f tz-mysql_cronJob.yaml_bak -n devops-dev
k apply -f tz-mysql_cronJob.yaml_bak -n devops-dev

kubectl -n devops-dev delete configmap tz-mysql-snapshot-script
kubectl -n devops-dev create configmap tz-mysql-snapshot-script --from-file=run.sh
