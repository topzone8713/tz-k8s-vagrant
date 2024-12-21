#!/usr/bin/env bash

#set -x
shopt -s expand_aliases
TZ_PROJECT=tz-local

alias k='kubectl --kubeconfig ~/.kube/config'

if [[ -f "/root/${TZ_PROJECT}/resource/dockerhub" ]]; then
  echo "## [ Make a slave env ] #############################"
  JENKINS_SLAVE_IMG=jenkins-slave
  BRANCH=latest
  mkdir -p /home/topzone/jenkins-slave
cat <<EOF | sudo tee /home/topzone/jenkins-slave/Dockerfile
  FROM jenkins/jnlp-slave
  ENTRYPOINT ["jenkins-slave"]
EOF

  sudo chown -Rf topzone:topzone /home/topzone/jenkins-slave
  cd /home/topzone/jenkins-slave
  docker image build -t ${JENKINS_SLAVE_IMG} .
  docker tag ${JENKINS_SLAVE_IMG}:${BRANCH} ${DOCKER_ID}/${JENKINS_SLAVE_IMG}:${BRANCH}
  docker push ${DOCKER_ID}/${JENKINS_SLAVE_IMG}:${BRANCH}
  echo "################################################"
fi
