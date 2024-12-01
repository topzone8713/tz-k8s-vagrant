#!/usr/bin/env bash

cd /topzone/projects/tgd-web

export AWS_ACCESS_KEY_ID=$(prop 'credentials' 'aws_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(prop 'credentials' 'aws_secret_access_key')
export AWS_REGION=$(prop 'config' 'region')
k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')
admin_password=$(prop 'project' 'admin_password')

GIT_BRANCH=k8s
GIT_URL="https://github.com/slkr/tgd-web.git"
TAG_ID="latest"
DOCKER_NAME="tgd-web"
DOCKER_NAME_NGINX="tgd-nginx"

AWS_REGION="ap-northeast-2"
ACCOUNT_ID="xxxxx"
CLUSTER_NAME="eks-main"
STAGING="dev"
#REPO_HOST="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
#IMAGE_TAG="${DOCKER_NAME}:${TAG_ID}"
#IMAGE_TAG_NGINX="${DOCKER_NAME_NGINX}:${TAG_ID}"
REPO_HOST="harbor.devops.topzone-k8s.topzone.me"
IMAGE_TAG="${DOCKER_NAME}/repository:${TAG_ID}"
IMAGE_TAG_NGINX="${DOCKER_NAME_NGINX}/repository:${TAG_ID}"
REPOSITORY_TAG="${REPO_HOST}/${IMAGE_TAG}"
REPOSITORY_TAG_NGINX="${REPO_HOST}/${IMAGE_TAG_NGINX}"

aws s3 cp s3://${DOCKER_NAME}-${CLUSTER_NAME}/conf/${STAGING}/config.php ./application/config/ --profile ${CLUSTER_NAME}
aws s3 cp s3://${DOCKER_NAME}-${CLUSTER_NAME}/conf/${STAGING}/database.php ./application/config/ --profile ${CLUSTER_NAME}
aws s3 cp s3://${DOCKER_NAME}-${CLUSTER_NAME}/conf/${STAGING}/twitch.php ./application/config/ --profile ${CLUSTER_NAME}
aws s3 cp s3://${DOCKER_NAME}-${CLUSTER_NAME}/conf/${STAGING}/aws.php ./application/config/ --profile ${CLUSTER_NAME}

bash ./k8s/config.sh ${GIT_BRANCH} ${STAGING}

sudo chown -Rf topzone:topzone /var/run/docker.sock
#aws ecr get-login-password --region ${AWS_REGION} \
#  | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

sudo vi /etc/docker/daemon.json
{
  "insecure-registries":["harbor.devops.${k8s_project}.${k8s_domain}"]
}
sudo systemctl restart docker

admin_password=Harbor12345
docker login harbor.devops.${k8s_project}.${k8s_domain} -u="admin" -p="${admin_password}"

#docker container stop $(docker container ls -a -q) && docker system prune -a -f --volumes
docker build -f docker/local/tgdBase.Dockerfile -t ${REPO_HOST}/tgd-web-phpbase/repository:latest .
docker push ${REPO_HOST}/tgd-web-phpbase/repository:latest

docker build -f docker/local/tgdWeb.Dockerfile -t ${REPOSITORY_TAG} .
docker push ${REPOSITORY_TAG}

docker build -f docker/local/tgdNginx.Dockerfile -t ${REPOSITORY_TAG_NGINX} .
docker push ${REPOSITORY_TAG_NGINX}

echo $REPOSITORY_TAG
echo $REPOSITORY_TAG_NGINX

docker image ls
#docker run ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DOCKER_NAME}

#aws ecr create-repository --repository-name "${DOCKER_NAME_NGINX}" || true
#REPO_URL=$(aws ecr describe-repositories --repository-name "${DOCKER_NAME_NGINX}" | jq '.repositories[].repositoryUri' | tr -d '"')
#echo "REPO_URL: ${REPO_URL}"
#aws ecr get-login-password --region ${AWS_REGION} \
#  | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
