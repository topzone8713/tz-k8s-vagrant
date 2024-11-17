#!/bin/bash

#set -x

WORKING_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd ${WORKING_DIR}

if [[ "$1" == "reload" ]]; then
  echo "Vagrant reload!"
  vagrant reload
  exit 0
elif [[ "$1" == "halt" ]]; then
  echo "Vagrant halt!"
  vagrant halt
  exit 0
elif [[ "$1" == "remove" ]]; then
  vagrant destroy -f
  exit 0
fi

echo -n "Do you want to make a jenkins on k8s in Vagrant Master / Slave? (M/S) "
read A_ENV

MYKEY=tz_rsa
if [ ! -f .ssh/${MYKEY} ]; then
  mkdir -p .ssh \
    && cd .ssh \
    && ssh-keygen -t rsa -C ${MYKEY} -P "" -f ${MYKEY} -q
fi

cp -Rf Vagrantfile Vagrantfile.bak
if [[ "${A_ENV}" == "M" ]]; then
  cp -Rf ./scripts/local/Vagrantfile Vagrantfile
  vagrant up --provider=virtualbox
  vagrant ssh kube-master -- -t 'bash /vagrant/scripts/local/kubespray.sh'
elif [[ "${A_ENV}" == "S" ]]; then
  cp -Rf ./scripts/local/Vagrantfile_slave Vagrantfile
  vagrant up --provider=virtualbox
#  vagrant ssh kube-slave -- -t 'bash /vagrant/scripts/local/node.sh'
  PROJECTS=(kube-slave-1 kube-slave-2 kube-slave-3)
  echo "" > info
  INC_CNT=0
  for item in "${PROJECTS[@]}"; do
    let "INC_CNT=INC_CNT+1"
    IP=`vagrant ssh kube-slave-${INC_CNT} -c "ifconfig" | grep eth1 -A 1 | tail -n 1 | awk '{print $2}'`
    echo kube-slave-${INC_CNT} ansible_host=${IP} ip=${IP} ansible_user=root ansible_ssh_private_key_file=/root/.ssh/tz_rsa ansible_ssh_extra_args='-o StrictHostKeyChecking=no' ansible_port=22 >> info
  done

  INC_CNT=0
  for item in "${PROJECTS[@]}"; do
    let "INC_CNT=INC_CNT+1"
    IP=`vagrant ssh kube-slave-${INC_CNT} -c "ifconfig" | grep eth1 -A 1 | tail -n 1 | awk '{print $2}'`
    echo ${IP}   kube-slave-${INC_CNT} >> info
  done
fi

mv Vagrantfile.bak Vagrantfile

exit 0

vagrant status
vagrant snapshot list

vagrant ssh kube-master
vagrant ssh kube-node-1
vagrant ssh kube-node-2

vagrant ssh kube-slave-1
vagrant ssh kube-slave-2
vagrant ssh kube-slave-3

vagrant reload
vagrant snapshot save kube-master kube-master_python --force

