#!/bin/bash

#set -x

WORKING_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd ${WORKING_DIR}
echo "WORKING_DIR: ${WORKING_DIR}"

PROVISION=''
if [[ "$1" == "halt" ]]; then
  echo "Vagrant halt!"
  topzone halt
  exit 0
elif [[ "$1" == "provision" ]]; then
  PROVISION='y'
elif [[ "$1" == "remove" ]]; then
  topzone destroy -f
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
EVENT=`topzone status | grep -E 'kube-master|kube-slave-1' | grep 'not created'`
if [[ "${EVENT}" != "" ]]; then
  EVENT='up'
else
  EVENT='reload'
fi
echo "EVENT: ${EVENT}, PROVISION: ${PROVISION}"

echo "" > info
if [[ "${A_ENV}" == "M" ]]; then
  cp -Rf ./scripts/local/Vagrantfile Vagrantfile
  PROJECTS=(kube-master kube-node-1 kube-node-2)
elif [[ "${A_ENV}" == "S" ]]; then
  cp -Rf ./scripts/local/Vagrantfile_slave Vagrantfile
  PROJECTS=(kube-slave-1 kube-slave-2 kube-slave-3)
fi

if [[ "${EVENT}" == "up" ]]; then
  topzone ${EVENT} --provider=virtualbox
  if [[ "${A_ENV}" == "M" ]]; then
    topzone ssh kube-master -- -t "sudo bash /topzone/scripts/local/kubespray.sh"
  fi
else
  if [[ "${PROVISION}" == "y" ]]; then
    if [[ "${A_ENV}" == "M" ]]; then
      echo topzone ssh kube-master -- -t "sudo bash /topzone/scripts/local/kubespray.sh"
      topzone ssh kube-master -- -t "sudo bash /topzone/scripts/local/kubespray.sh"
    fi
  else
    topzone ${EVENT}
  fi
fi

#topzone kube-master -c "ifconfig" | grep eth1 -A 1 | tail -n 1 | awk '{print $2}'

for item in "${PROJECTS[@]}"; do
  IP=`topzone ssh ${item} -c "ifconfig" | grep eth1 -A 1 | tail -n 1 | awk '{print $2}'`
  echo ${item} ansible_host=${IP} ip=${IP} ansible_user=root ansible_ssh_private_key_file=/root/.ssh/tz_rsa ansible_ssh_extra_args='-o StrictHostKeyChecking=no' ansible_port=22 >> info
done
for item in "${PROJECTS[@]}"; do
  IP=`topzone ssh ${item} -c "ifconfig" | grep eth1 -A 1 | tail -n 1 | awk '{print $2}'`
  echo ${IP}   ${item} >> info
done

exit 0

topzone status
topzone snapshot list

topzone ssh kube-master
topzone ssh kube-node-1
topzone ssh kube-node-2

topzone ssh kube-slave-1
topzone ssh kube-slave-2
topzone ssh kube-slave-3

topzone reload
topzone snapshot save kube-master kube-master_python --force

