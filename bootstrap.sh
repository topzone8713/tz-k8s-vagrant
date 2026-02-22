#!/bin/bash

export MSYS_NO_PATHCONV=1
export tz_project=devops-utils

#set -x

WORKING_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd ${WORKING_DIR}
echo "WORKING_DIR: ${WORKING_DIR}"

# OS detection (mac, linux, windows for Git Bash/MSYS2)
detect_platform() {
  case "$OSTYPE" in
    darwin*)  echo "mac" ;;
    linux-gnu*) echo "linux" ;;
    msys|cygwin|msys2) echo "windows" ;;
    *) echo "linux" ;;
  esac
}
PLATFORM=$(detect_platform)

if [[ "$1" == "help" || "$1" == "-h" || "$1" == "/help" ]]; then
cat <<EOF
  - bash bootstrap.sh [S|M]
      S=Slave(1 master + 3 nodes), M=Master(1 master + 2 nodes). Default: M.
      If it's from scratch, it means "vagrant up" else "vagrant reload"
  - bash bootstrap.sh halt
      "vagrant halt"
  - bash bootstrap.sh reload
      "vagrant reload"
  - bash bootstrap.sh provision
      "run kubespray.sh and other scripts"
  - bash bootstrap.sh status
      "vagrant status"
  - bash bootstrap.sh save
      "vagrant save snapshot xxx"
  - bash bootstrap.sh restore xxx
      "vagrant restore snapshot xxx"
  - bash bootstrap.sh delete xxx
      "vagrant restore delete xxx"
  - bash bootstrap.sh ssh
      "vagrant ssh kube-master"
  - bash bootstrap.sh remove
      "vagrant destroy -f"
EOF
exit 0
fi

PROVISION=''
if [[ "$1" == "halt" ]]; then
  echo "vagrant halt"
  vagrant halt
  exit 0
elif [[ "$1" == "status" ]]; then
  echo "vagrant status"
  vagrant status
  exit 0
elif [[ "$1" == "ssh" ]]; then
  echo "vagrant ssh kube-master"
  vagrant ssh kube-master
  exit 0
elif [[ "$1" == "provision" ]]; then
  PROVISION='y'
elif [[ "$1" == "remove" ]]; then
  echo "vagrant destroy -f"
  # Copy Vagrantfile before destroy (A_ENV needed)
  if [ -z "${A_ENV}" ]; then
    [ -f info ] && A_ENV_CHECK=$(grep 'kube-master' Vagrantfile 2>/dev/null) && [ -n "$A_ENV_CHECK" ] && A_ENV="M" || A_ENV="S"
    [ -z "${A_ENV}" ] && A_ENV="M"
  fi
  if [[ "${A_ENV}" == "M" ]]; then
    cp -Rf ./scripts/local/Vagrantfile Vagrantfile
  elif [[ "${A_ENV}" == "S" ]]; then
    cp -Rf ./scripts/local/Vagrantfile_slave Vagrantfile
  fi
  # Kill stuck vagrant/ruby (Windows: taskkill)
  if [[ "$PLATFORM" == "windows" ]]; then
    taskkill //F //IM vagrant.exe 2>/dev/null || true
    taskkill //F //IM ruby.exe 2>/dev/null || true
    sleep 2
  else
    pkill -9 -f 'vagrant|ruby.*vagrant' 2>/dev/null || true
    sleep 2
  fi
  VAGRANT_DESTROY_OUTPUT=$(vagrant destroy -f 2>&1)
  VAGRANT_DESTROY_EXIT=$?
  if [ $VAGRANT_DESTROY_EXIT -ne 0 ] && echo "$VAGRANT_DESTROY_OUTPUT" | grep -qi "E_ACCESSDENIED\|LockMachine\|object functionality is limited"; then
    echo "WARNING: VirtualBox VM lock. Attempting VBoxManage unregistervm..."
    VBOX=""
    command -v VBoxManage >/dev/null 2>&1 && VBOX="VBoxManage"
    [ -z "$VBOX" ] && [ -f "/Applications/VirtualBox.app/Contents/MacOS/VBoxManage" ] && VBOX="/Applications/VirtualBox.app/Contents/MacOS/VBoxManage"
    [ -z "$VBOX" ] && [ -f "/usr/bin/VBoxManage" ] && VBOX="/usr/bin/VBoxManage"
    [ -z "$VBOX" ] && [ -f "/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" ] && VBOX="/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"
    if [ -n "$VBOX" ] && [ -d .vagrant/machines ]; then
      for f in .vagrant/machines/*/virtualbox/id; do
        [ -f "$f" ] && UUID=$(cat "$f" 2>/dev/null | tr -d ' \r\n') && [ -n "$UUID" ] && $VBOX unregistervm "$UUID" --delete 2>/dev/null || true
      done
      rm -Rf .vagrant
    fi
  fi
  git checkout Vagrantfile
  rm -Rf info
  exit 0
elif [[ "$1" == "docker" ]]; then
  DOCKER_NAME=`docker ps | grep docker-${tz_project} | awk '{print $1}'`
  echo "======= DOCKER_NAME: ${DOCKER_NAME}"
  if [[ "${DOCKER_NAME}" == "" ]]; then
    bash tz-local/docker/install.sh
  fi
  if [[ "$1" == "sh" ]]; then
    docker exec -it `docker ps | grep docker-${tz_project} | awk '{print $1}'` bash
    exit 0
  fi

#  echo docker exec -it ${DOCKER_NAME} bash /vagrant/tz-local/docker/init2.sh
#  docker exec -it ${DOCKER_NAME} bash /vagrant/tz-local/docker/init2.sh
fi

# A_ENV: 환경변수 > 인자(S/M) > 기본값 "M"
if [ -n "${A_ENV}" ]; then
  echo "Using A_ENV from environment: ${A_ENV}"
elif [[ "$1" == "S" || "$1" == "s" ]]; then
  A_ENV="S"
  echo "Using A_ENV=S (Slave) from argument"
elif [[ "$1" == "M" || "$1" == "m" ]]; then
  A_ENV="M"
  echo "Using A_ENV=M (Master) from argument"
else
  A_ENV="M"
  echo "Using default A_ENV=M (Master)"
fi

# info 파일이 있고, 환경변수가 없으면 Vagrantfile에서 확인
if [ -f info ] && [ -z "${A_ENV}" ]; then
  A_ENV_CHECK=`cat Vagrantfile | grep 'kube-master'`
  if [[ "${A_ENV_CHECK}" != "" ]]; then
    A_ENV="M"
  else
    A_ENV="S"
  fi
fi

MYKEY=tz_rsa
if [ ! -f .ssh/${MYKEY} ]; then
  mkdir -p .ssh \
    && cd .ssh \
    && ssh-keygen -t rsa -C ${MYKEY} -P "" -f ${MYKEY} -q
  echo "Make ssh key files: ${MYKEY}"
else
  echo "Use existing ssh key files: ${MYKEY}"
fi

# Copy Vagrantfile before vagrant status (avoids stale root Vagrantfile)
if [[ "${A_ENV}" == "M" ]]; then
  cp -Rf ./scripts/local/Vagrantfile Vagrantfile
elif [[ "${A_ENV}" == "S" ]]; then
  cp -Rf ./scripts/local/Vagrantfile_slave Vagrantfile
fi
cp -Rf Vagrantfile Vagrantfile.bak
if [[ "${1}" == "save" || "${1}" == "restore" || "${1}" == "delete" || "${1}" == "list" ]]; then
  EVENT=${1}
else
  EVENT=`vagrant status | grep -E 'kube-master|kube-slave-1' | grep 'not created'`
  if [[ "${EVENT}" != "" ]]; then
    EVENT='up'
  else
    EVENT='reload'
  fi
fi
echo "EVENT: ${EVENT}, Type: ${A_ENV}, PROVISION: ${PROVISION}"

if [[ "${A_ENV}" == "M" ]]; then
  cp -Rf ./scripts/local/Vagrantfile Vagrantfile
  PROJECTS=(kube-master kube-node-1 kube-node-2)
elif [[ "${A_ENV}" == "S" ]]; then
  cp -Rf ./scripts/local/Vagrantfile_slave Vagrantfile
  PROJECTS=(kube-slave-1 kube-slave-2 kube-slave-3)
fi

if [[ "${EVENT}" == "up" ]]; then
  echo "- PC Type: ${A_ENV}" > info
  echo "##################################################################################"
  echo 'vagrant ${EVENT} --provider=virtualbox'
  echo "##################################################################################"
  sleep 5
  vagrant ${EVENT} --provider=virtualbox
  if [[ "${A_ENV}" == "M" ]]; then
    echo "##################################################################################"
    echo 'vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/kubespray.sh"'
    echo "##################################################################################"
    sleep 5
    vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/kubespray.sh"
    echo "##################################################################################"
    echo 'vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/master_01.sh"'
    echo "##################################################################################"
    sleep 5
    vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/master_01.sh"
  fi
elif [[ "${EVENT}" == "save" || "${EVENT}" == "restore" || "${EVENT}" == "delete" || "${EVENT}" == "list" ]]; then
  if [[ "${EVENT}" == "save" ]]; then
    item=$(date +"%Y%m%d-%H%M%S")
    echo vagrant snapshot ${EVENT} ${item}
    vagrant snapshot ${EVENT} ${item}
  elif [[ "${EVENT}" == "restore" || "${EVENT}" == "delete" ]]; then
    echo vagrant snapshot ${EVENT} ${2}
    vagrant snapshot ${EVENT} ${2}
  fi
  if [[ "${EVENT}" != "delete" ]]; then
    echo vagrant snapshot list
    vagrant snapshot list
  fi
  exit 0
else
  if [[ "${PROVISION}" == "y" ]]; then
    if [[ "${A_ENV}" == "M" ]]; then
      echo "##################################################################################"
      echo 'vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/kubespray.sh"'
      echo "##################################################################################"
      sleep 5
      vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/kubespray.sh"
      echo "##################################################################################"
      echo 'vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/master_01.sh"'
      echo "##################################################################################"
      sleep 5
      vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/master_01.sh"
    fi
  else
    sleep 5
    echo "##################################################################################"
    echo "vagrant ${EVENT}"
    echo "##################################################################################"
    vagrant ${EVENT}
  fi
fi

#vagrant kube-master -c "ifconfig" | grep eth1 -A 1 | tail -n 1 | awk '{print $2}'

for item in "${PROJECTS[@]}"; do
  IP=`vagrant ssh ${item} -c "ifconfig" | grep eth1 -A 1 | tail -n 1 | awk '{print $2}'`
  echo ${item} ansible_host=${IP} ip=${IP} ansible_user=root ansible_ssh_private_key_file=/root/.ssh/tz_rsa ansible_ssh_extra_args='-o StrictHostKeyChecking=no' ansible_port=22 >> info
done
for item in "${PROJECTS[@]}"; do
  IP=`vagrant ssh ${item} -c "ifconfig" | grep eth1 -A 1 | tail -n 1 | awk '{print $2}'`
  echo ${IP}   ${item} >> info
done

cat info

exit 0

# install in docker
export docker_user="topzone8713"
bash /vagrant/tz-local/docker/init2.sh

# remove all resources
docker exec -it ${DOCKER_NAME} bash
bash /vagrant/scripts/k8s_remove_all.sh
bash /vagrant/scripts/k8s_remove_all.sh cleanTfFiles

#docker container stop $(docker container ls -a -q) && docker system prune -a -f --volumes
