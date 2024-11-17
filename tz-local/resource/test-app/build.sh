#!/usr/bin/env bash

#set -x
shopt -s expand_aliases
TZ_PROJECT=tz-local

alias k='kubectl --kubeconfig ~/.kube/config'

if [[ -f "/root/${TZ_PROJECT}/resource/dockerhub" ]]; then
  echo "## [ Make a slave env ] #############################"
  JENKINS_SLAVE_IMG=jenkins-slave
  BRANCH=latest
  mkdir -p /home/vagrant/jenkins-slave
cat <<EOF | sudo tee /home/vagrant/jenkins-slave/Dockerfile
  FROM jenkins/jnlp-slave
  ENTRYPOINT ["jenkins-slave"]
EOF

  sudo chown -Rf vagrant:vagrant /home/vagrant/jenkins-slave
  cd /home/vagrant/jenkins-slave
  docker image build -t ${JENKINS_SLAVE_IMG} .
  docker tag ${JENKINS_SLAVE_IMG}:${BRANCH} ${DOCKER_ID}/${JENKINS_SLAVE_IMG}:${BRANCH}
  docker push ${DOCKER_ID}/${JENKINS_SLAVE_IMG}:${BRANCH}
  echo "################################################"
fi
