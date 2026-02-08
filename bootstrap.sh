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
    *) echo "linux" ;;  # default to linux semantics
  esac
}
PLATFORM=$(detect_platform)
echo "PLATFORM: ${PLATFORM}"

if [[ "$1" == "help" || "$1" == "-h" || "$1" == "/help" ]]; then
cat <<EOF
  - bash bootstrap.sh
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
      "vagrant snapshot delete xxx"
  - bash bootstrap.sh list
      "vagrant snapshot list"
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
  
  # Check for A_ENV: env var → resources/project → default M
  if [ -z "${A_ENV}" ] && [ -f "${WORKING_DIR}/resources/project" ]; then
    A_ENV=$(grep "^A_ENV=" "${WORKING_DIR}/resources/project" 2>/dev/null | cut -d= -f2 | tr -d ' \r\n')
  fi
  if [ -z "${A_ENV}" ]; then
    A_ENV="M"
  fi
  
  # Copy appropriate Vagrantfile before destroy
  if [[ "${A_ENV}" == "M" ]]; then
    cp -Rf ./scripts/local/Vagrantfile Vagrantfile
  elif [[ "${A_ENV}" == "S" ]]; then
    cp -Rf ./scripts/local/Vagrantfile_slave Vagrantfile
  elif [[ "${A_ENV}" == "S2" ]]; then
    cp -Rf ./scripts/local/Vagrantfile_slave2 Vagrantfile
  fi
  
  # Kill any stuck vagrant/ruby processes before destroy
  echo "Checking for stuck vagrant processes..."
  if [[ "$PLATFORM" == "windows" ]]; then
    STUCK_PROCESSES=$(tasklist 2>/dev/null | grep -iE 'vagrant|ruby' || true)
    if [ -n "$STUCK_PROCESSES" ]; then
      echo "Found stuck vagrant processes. Killing them..."
      taskkill //F //IM vagrant.exe 2>/dev/null || true
      taskkill //F //IM ruby.exe 2>/dev/null || true
      sleep 2
    fi
  else
    STUCK_PROCESSES=$(ps aux | grep -E '[v]agrant|[r]uby.*vagrant' | grep -v grep || true)
    if [ -n "$STUCK_PROCESSES" ]; then
      echo "Found stuck vagrant processes. Killing them..."
      pkill -9 -f 'vagrant|ruby.*vagrant' 2>/dev/null || true
      sleep 2
    fi
  fi
  
  # Wait for locks to be released (max 30 seconds)
  LOCK_WAIT=0
  MAX_LOCK_WAIT=30
  while [ $LOCK_WAIT -lt $MAX_LOCK_WAIT ]; do
    if [[ "$PLATFORM" == "windows" ]]; then
      if ! tasklist 2>/dev/null | grep -qiE 'vagrant|ruby'; then
        break
      fi
    else
      if ! ps aux | grep -E '[v]agrant|[r]uby.*vagrant' | grep -v grep > /dev/null 2>&1; then
        break
      fi
    fi
    echo "Waiting for vagrant processes to finish... (${LOCK_WAIT}s/${MAX_LOCK_WAIT}s)"
    sleep 2
    LOCK_WAIT=$((LOCK_WAIT + 2))
  done
  
  # Try vagrant destroy
  VAGRANT_DESTROY_OUTPUT=$(vagrant destroy -f 2>&1)
  VAGRANT_DESTROY_EXIT=$?
  
  # Check for lock errors
  if echo "$VAGRANT_DESTROY_OUTPUT" | grep -qi "another process is already executing\|Vagrant locks each machine"; then
    echo "WARNING: Vagrant lock detected. Attempting to resolve..."
    
    # Kill all vagrant/ruby processes more aggressively
    if [[ "$PLATFORM" == "windows" ]]; then
      taskkill //F //IM vagrant.exe 2>/dev/null || true
      taskkill //F //IM ruby.exe 2>/dev/null || true
    else
      pkill -9 -f 'vagrant' 2>/dev/null || true
      pkill -9 -f 'ruby.*vagrant' 2>/dev/null || true
    fi
    sleep 3
    
    # Remove lock files if they exist
    find .vagrant -name "*.lock" -delete 2>/dev/null || true
    
    # Try destroy again
    echo "Retrying vagrant destroy..."
    vagrant destroy -f
  elif [ $VAGRANT_DESTROY_EXIT -ne 0 ]; then
    echo "WARNING: vagrant destroy returned non-zero exit code: $VAGRANT_DESTROY_EXIT"
    echo "Output: $VAGRANT_DESTROY_OUTPUT"
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

# A_ENV 결정 우선순위: 1) 환경변수 2) resources/project 3) 기본값 M
PROJECT_FILE="${WORKING_DIR}/resources/project"

if [ -n "${A_ENV}" ]; then
  # 환경변수가 있으면 사용. resources/project에 A_ENV 없으면 추가
  echo "Using A_ENV from environment: ${A_ENV}"
  if [ -f "${PROJECT_FILE}" ]; then
    if ! grep -q "^A_ENV=" "${PROJECT_FILE}" 2>/dev/null; then
      echo "A_ENV=${A_ENV}" >> "${PROJECT_FILE}"
      echo "Added A_ENV=${A_ENV} to ${PROJECT_FILE}"
    fi
  else
    mkdir -p "$(dirname "${PROJECT_FILE}")"
    echo "A_ENV=${A_ENV}" >> "${PROJECT_FILE}"
    echo "Created ${PROJECT_FILE} with A_ENV=${A_ENV}"
  fi
else
  # 환경변수가 없으면 resources/project에서 확인
  if [ -f "${PROJECT_FILE}" ]; then
    A_ENV_FROM_FILE=$(grep "^A_ENV=" "${PROJECT_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' \r\n')
    if [ -n "${A_ENV_FROM_FILE}" ]; then
      A_ENV="${A_ENV_FROM_FILE}"
      echo "Using A_ENV from ${PROJECT_FILE}: ${A_ENV}"
    fi
  fi
  if [ -z "${A_ENV}" ]; then
    A_ENV="M"
    echo "Using default A_ENV=M (Master)"
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

cp -Rf Vagrantfile Vagrantfile.bak
if [[ "${1}" == "save" || "${1}" == "restore" || "${1}" == "delete" || "${1}" == "list" ]]; then
  EVENT=${1}
else
  EVENT=`vagrant status | grep -E 'kube-master|kube-slave-1|kube-slave-4' | grep 'not created'`
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
elif [[ "${A_ENV}" == "S2" ]]; then
  cp -Rf ./scripts/local/Vagrantfile_slave2 Vagrantfile
  PROJECTS=(kube-slave-4 kube-slave-5 kube-slave-6)
fi

if [[ "${EVENT}" == "up" ]]; then
  echo "- PC Type: ${A_ENV}" > info
  echo "##################################################################################"
  echo 'vagrant ${EVENT} --provider=virtualbox'
  echo "##################################################################################"
  sleep 5
  # Run vagrant up with real-time output, also capture to variable for analysis
  VAGRANT_UP_OUTPUT=$(vagrant ${EVENT} --provider=virtualbox 2>&1 | tee /dev/tty)
  VAGRANT_UP_EXIT_CODE=${PIPESTATUS[0]}
  
  # Check if vagrant up failed or if any VMs were not created
  if [ $VAGRANT_UP_EXIT_CODE -ne 0 ]; then
    echo "WARNING: vagrant ${EVENT} exited with code $VAGRANT_UP_EXIT_CODE"
    echo "Checking which VMs were created..."
  fi
  
  # Analyze output for errors or skipped VMs
  if echo "$VAGRANT_UP_OUTPUT" | grep -qi "error\|failed\|fatal"; then
    echo "ERROR: vagrant ${EVENT} encountered errors. Analyzing..."
    echo "$VAGRANT_UP_OUTPUT" | grep -i "error\|failed\|fatal" | head -10
  fi

  # Check which VMs were actually attempted in vagrant up output
  echo "##################################################################################"
  echo "Analyzing vagrant up output to see which VMs were triggered..."
  echo "##################################################################################"
  for item in "${PROJECTS[@]}"; do
    if echo "$VAGRANT_UP_OUTPUT" | grep -qi "${item}"; then
      echo "✓ ${item} was mentioned in vagrant up output"
      # Check if it was an error
      if echo "$VAGRANT_UP_OUTPUT" | grep -i "${item}" | grep -qi "error\|failed"; then
        echo "  ⚠ ERROR detected for ${item}:"
        echo "$VAGRANT_UP_OUTPUT" | grep -i "${item}" | grep -i "error\|failed" | head -3
      fi
    else
      echo "✗ ${item} was NOT mentioned in vagrant up output (may not have been triggered)"
    fi
  done
  
  # Check if any VMs failed to start and retry individually
  echo "##################################################################################"
  echo "Checking if all VMs were created..."
  echo "##################################################################################"
  MISSING_VMS=()
  # Find VBoxManage command (handle different platforms)
  VBOXMANAGE_CMD=""
  if command -v VBoxManage > /dev/null 2>&1; then
    VBOXMANAGE_CMD="VBoxManage"
  elif [ -f "/Applications/VirtualBox.app/Contents/MacOS/VBoxManage" ]; then
    VBOXMANAGE_CMD="/Applications/VirtualBox.app/Contents/MacOS/VBoxManage"
  elif [ -f "/usr/bin/VBoxManage" ]; then
    VBOXMANAGE_CMD="/usr/bin/VBoxManage"
  elif [ -f "/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" ]; then
    VBOXMANAGE_CMD="/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"
  elif [ -f "/mingw64/bin/VBoxManage.exe" ]; then
    VBOXMANAGE_CMD="/mingw64/bin/VBoxManage.exe"
  fi

  for item in "${PROJECTS[@]}"; do
    STATUS=$(vagrant status ${item} 2>/dev/null | grep "${item}" | grep -E "running|not created|poweroff")
    if echo "$STATUS" | grep -q "not created"; then
      # Check if VirtualBox VM actually exists (more reliable than directory check)
      if [ -n "$VBOXMANAGE_CMD" ]; then
        VBOX_VM_EXISTS=$($VBOXMANAGE_CMD list vms 2>/dev/null | grep -q "${item}" && echo "yes" || echo "no")
        VBOX_VM_RUNNING=$($VBOXMANAGE_CMD list runningvms 2>/dev/null | grep -q "${item}" && echo "yes" || echo "no")
      else
        VBOX_VM_EXISTS="no"
        VBOX_VM_RUNNING="no"
      fi
      
      if [ "$VBOX_VM_EXISTS" = "yes" ] || [ "$VBOX_VM_RUNNING" = "yes" ]; then
        echo "INFO: ${item} shows 'not created' but VirtualBox VM exists. VM may be starting up, will wait..."
        # VM exists but vagrant doesn't recognize it - wait a bit for it to be ready
        sleep 10
        # Re-check status after wait
        STATUS_AFTER_WAIT=$(vagrant status ${item} 2>/dev/null | grep "${item}" | grep -E "running|not created|poweroff")
        if echo "$STATUS_AFTER_WAIT" | grep -q "not created"; then
          echo "WARNING: ${item} still shows 'not created' after wait. Will retry creation..."
          MISSING_VMS+=("${item}")
        fi
      else
        echo "WARNING: ${item} was not created (no VirtualBox VM found). Will retry..."
        MISSING_VMS+=("${item}")
      fi
    fi
  done
  
  # Retry creating missing VMs individually
  if [ ${#MISSING_VMS[@]} -gt 0 ]; then
    echo "##################################################################################"
    echo "Retrying creation of missing VMs: ${MISSING_VMS[@]}"
    echo "##################################################################################"
    for item in "${MISSING_VMS[@]}"; do
      echo "Creating ${item}..."
      # Clean up any stale vagrant metadata if VM doesn't exist
      if [ -n "$VBOXMANAGE_CMD" ] && [ ! -z "$($VBOXMANAGE_CMD list vms 2>/dev/null | grep "${item}")" ]; then
        echo "  Cleaning up stale VirtualBox VM for ${item}..."
        $VBOXMANAGE_CMD unregistervm "$($VBOXMANAGE_CMD list vms | grep "${item}" | awk -F'[{}]' '{print $2}')" --delete 2>/dev/null || true
      fi
      vagrant up ${item} --provider=virtualbox
      VAGRANT_UP_EXIT=$?
      
      # Check if VM was actually created despite exit code
      # Sometimes provisioning completes successfully but returns non-zero exit code
      if [ -n "$VBOXMANAGE_CMD" ]; then
        VBOX_VM_EXISTS=$($VBOXMANAGE_CMD list vms 2>/dev/null | grep -q "${item}" && echo "yes" || echo "no")
      else
        VBOX_VM_EXISTS="no"
      fi
      VAGRANT_STATUS=$(vagrant status ${item} 2>/dev/null | grep "${item}" | grep -E "running|not created|poweroff")
      
      if [ "$VBOX_VM_EXISTS" = "yes" ] || echo "$VAGRANT_STATUS" | grep -qE "running|poweroff"; then
        echo "✓ ${item} was created successfully (VM exists and is accessible)"
        # VM was created, continue even if vagrant up returned non-zero
      elif [ $VAGRANT_UP_EXIT -ne 0 ]; then
        echo "ERROR: Failed to create ${item} (exit code: $VAGRANT_UP_EXIT, VM does not exist)"
        echo "  Vagrant status: ${VAGRANT_STATUS}"
        echo "  VirtualBox VM exists: ${VBOX_VM_EXISTS}"
        exit 1
      fi
    done
  fi
  
  # Wait for all VMs to be running
  echo "##################################################################################"
  echo "Waiting for all VMs to be running..."
  echo "##################################################################################"
  MAX_WAIT=300  # 5 minutes max wait
  WAIT_COUNT=0
  while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    ALL_RUNNING=true
    for item in "${PROJECTS[@]}"; do
      STATUS=$(vagrant status ${item} 2>/dev/null | grep "${item}" | grep -E "running|not created|poweroff")
      if echo "$STATUS" | grep -q "not created"; then
        ALL_RUNNING=false
        break
      fi
    done
    if [ "$ALL_RUNNING" = true ]; then
      echo "✓ All VMs are running"
      break
    fi
    echo "Waiting for all VMs to be created... (${WAIT_COUNT}s/${MAX_WAIT}s)"
    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 5))
  done
  
  if [ "$ALL_RUNNING" != true ]; then
    echo "ERROR: Not all VMs are running after ${MAX_WAIT} seconds!"
    vagrant status
    exit 1
  fi
  
  # Static IP 설정 적용 (호스트-VM 통신을 위해)
  # Note: vm-network.sh requires bash 4+ for associative arrays
  if [ -f scripts/local/vm-network.sh ]; then
    echo "##################################################################################"
    echo 'Applying static IP configuration for host-VM communication'
    echo "##################################################################################"
    sleep 5
    # Try to find bash 4+ (required for associative arrays)
    BASH4_CMD=""
    if command -v bash > /dev/null 2>&1 && bash --version 2>/dev/null | grep -q "version [4-9]"; then
      BASH4_CMD="bash"
    elif [ -f "/opt/homebrew/bin/bash" ]; then
      BASH4_CMD="/opt/homebrew/bin/bash"
    elif [ -f "/usr/local/bin/bash" ]; then
      BASH4_CMD="/usr/local/bin/bash"
    elif [ -f "/usr/bin/bash" ]; then
      BASH4_CMD="/usr/bin/bash"
    elif [ -f "/mingw64/bin/bash.exe" ]; then
      BASH4_CMD="/mingw64/bin/bash.exe"
    fi
    
    if [ -n "$BASH4_CMD" ]; then
      $BASH4_CMD scripts/local/vm-network.sh apply-static-ip || echo "WARNING: vm-network.sh failed, but continuing..."
    else
      echo "WARNING: bash 4+ not found. Skipping vm-network.sh (requires bash 4+ for associative arrays)"
    fi
  elif [ -f scripts/local/apply-static-ip-ubuntu.sh ]; then
    echo "##################################################################################"
    echo 'Applying static IP configuration for host-VM communication'
    echo "##################################################################################"
    sleep 5
    bash scripts/local/apply-static-ip-ubuntu.sh
  elif [ -f scripts/local/apply-static-ip.sh ]; then
    echo "##################################################################################"
    echo 'Applying static IP configuration for host-VM communication'
    echo "##################################################################################"
    sleep 5
    bash scripts/local/apply-static-ip.sh
  fi
  
  if [[ "${A_ENV}" == "M" ]]; then
    # Verify all nodes are accessible via SSH before running kubespray
    echo "##################################################################################"
    echo "Verifying SSH connectivity to all nodes..."
    echo "##################################################################################"
    sleep 10  # Give VMs time to fully boot
    ALL_ACCESSIBLE=true
    for item in "${PROJECTS[@]}"; do
      if ! vagrant ssh ${item} -c "echo 'SSH test successful'" > /dev/null 2>&1; then
        echo "WARNING: ${item} is not accessible via SSH yet"
        ALL_ACCESSIBLE=false
      fi
    done
    
    if [ "$ALL_ACCESSIBLE" != true ]; then
      echo "WARNING: Some nodes are not accessible via SSH. Waiting 30 more seconds..."
      sleep 30
    fi
    
    # Fix network routing on all nodes before kubespray
    echo "##################################################################################"
    echo "Fixing network routing on all nodes for internet access..."
    echo "##################################################################################"
    for item in "${PROJECTS[@]}"; do
      echo "Fixing routing on ${item}..."
      vagrant ssh ${item} -c "sudo ip route del default via 192.168.0.1 dev eth1 2>/dev/null || true; sudo ip route del default via 10.0.2.2 dev eth0 2>/dev/null || true; sudo ip route add default via 10.0.2.2 dev eth0 2>/dev/null || true" > /dev/null 2>&1 || true
      # Verify internet connectivity
      if vagrant ssh ${item} -c "ping -c 2 8.8.8.8 > /dev/null 2>&1" 2>/dev/null; then
        echo "✓ ${item}: Internet access verified"
      else
        echo "⚠ ${item}: Internet access check failed (may still work)"
      fi
    done
    
    echo "##################################################################################"
    echo 'vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/kubespray.sh"'
    echo "##################################################################################"
    sleep 5
    if ! vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/kubespray.sh"; then
      echo "ERROR: kubespray.sh failed!"
      exit 1
    fi
    echo "##################################################################################"
    echo 'vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/master_01.sh"'
    echo "##################################################################################"
    sleep 5
    if ! vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/master_01.sh"; then
      echo "ERROR: master_01.sh failed!"
      exit 1
    fi
    
    # Copy kubeconfig to host ~/.kube/config after successful installation
    echo "##################################################################################"
    echo "Copying kubeconfig to host ~/.kube/config..."
    echo "##################################################################################"
    KUBECONFIG_SOURCE=""
    # Determine expected kubeconfig filename based on project directory name
    PROJECT_NAME=$(basename "${WORKING_DIR}" 2>/dev/null || echo "tz-k8s-vagrant")
    EXPECTED_KUBECONFIG=".ssh/kubeconfig_${PROJECT_NAME}"
    
    # Try to find kubeconfig file
    if [ -f "${EXPECTED_KUBECONFIG}" ]; then
      KUBECONFIG_SOURCE="${EXPECTED_KUBECONFIG}"
    else
      # Fallback: try to find any kubeconfig_* file
      KUBECONFIG_SOURCE=$(find .ssh -name "kubeconfig_*" -type f 2>/dev/null | head -1)
    fi
    
    if [ -n "$KUBECONFIG_SOURCE" ] && [ -f "$KUBECONFIG_SOURCE" ]; then
      echo "Found kubeconfig: $KUBECONFIG_SOURCE"
      mkdir -p ~/.kube
      cp -f "$KUBECONFIG_SOURCE" ~/.kube/config
      chmod 600 ~/.kube/config
      
      # Update server address to use kube-master IP (192.168.0.100) for direct access
      # The kubeconfig from VM has 192.168.0.100 already set by kubespray.sh
      # But we ensure it's correct for host access
      if grep -q "server: https://" ~/.kube/config; then
        # Check if server is already set to 192.168.0.100, if not update it
        if ! grep -q "server: https://192.168.0.100:6443" ~/.kube/config; then
          if [[ "$PLATFORM" == "mac" ]]; then
            sed -i '' "s|server: https://.*:6443|server: https://192.168.0.100:6443|g" ~/.kube/config
          else
            sed -i "s|server: https://.*:6443|server: https://192.168.0.100:6443|g" ~/.kube/config
          fi
        fi
      fi
      
      # Add insecure-skip-tls-verify to cluster configuration to avoid TLS certificate errors
      # This is safe for development environments
      if ! grep -q "insecure-skip-tls-verify" ~/.kube/config; then
        # Find the cluster section and add insecure-skip-tls-verify after server line
        if [[ "$PLATFORM" == "mac" ]]; then
          sed -i '' '/server: https:\/\/192\.168\.0\.100:6443/a\
    insecure-skip-tls-verify: true
' ~/.kube/config
        else
          sed -i '/server: https:\/\/192\.168\.0\.100:6443/a\    insecure-skip-tls-verify: true' ~/.kube/config
        fi
      fi
      
      echo "✓ kubeconfig copied to ~/.kube/config"
      echo "  Server: https://192.168.0.100:6443"
      echo "  insecure-skip-tls-verify: true (for development)"
    else
      echo "⚠ WARNING: kubeconfig file not found in .ssh directory"
      echo "  Expected: ${EXPECTED_KUBECONFIG} or .ssh/kubeconfig_*"
      echo "  You may need to copy it manually or run access-k8s-from-host.sh"
    fi
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
      
      # Copy kubeconfig to host ~/.kube/config after successful installation
      echo "##################################################################################"
      echo "Copying kubeconfig to host ~/.kube/config..."
      echo "##################################################################################"
      KUBECONFIG_SOURCE=""
      # Determine expected kubeconfig filename based on project directory name
      PROJECT_NAME=$(basename "${WORKING_DIR}" 2>/dev/null || echo "tz-k8s-vagrant")
      EXPECTED_KUBECONFIG=".ssh/kubeconfig_${PROJECT_NAME}"
      
      # Try to find kubeconfig file
      if [ -f "${EXPECTED_KUBECONFIG}" ]; then
        KUBECONFIG_SOURCE="${EXPECTED_KUBECONFIG}"
      else
        # Fallback: try to find any kubeconfig_* file
        KUBECONFIG_SOURCE=$(find .ssh -name "kubeconfig_*" -type f 2>/dev/null | head -1)
      fi
      
      if [ -n "$KUBECONFIG_SOURCE" ] && [ -f "$KUBECONFIG_SOURCE" ]; then
        echo "Found kubeconfig: $KUBECONFIG_SOURCE"
        mkdir -p ~/.kube
        cp -f "$KUBECONFIG_SOURCE" ~/.kube/config
        chmod 600 ~/.kube/config
        
        # Update server address to use kube-master IP (192.168.0.100) for direct access
        # The kubeconfig from VM has 192.168.0.100 already set by kubespray.sh
        # But we ensure it's correct for host access
        if grep -q "server: https://" ~/.kube/config; then
          # Check if server is already set to 192.168.0.100, if not update it
          if ! grep -q "server: https://192.168.0.100:6443" ~/.kube/config; then
            if [[ "$PLATFORM" == "mac" ]]; then
              sed -i '' "s|server: https://.*:6443|server: https://192.168.0.100:6443|g" ~/.kube/config
            else
              sed -i "s|server: https://.*:6443|server: https://192.168.0.100:6443|g" ~/.kube/config
            fi
          fi
        fi
        
        # Add insecure-skip-tls-verify to cluster configuration to avoid TLS certificate errors
        # This is safe for development environments
        if ! grep -q "insecure-skip-tls-verify" ~/.kube/config; then
          # Find the cluster section and add insecure-skip-tls-verify after server line
          if [[ "$PLATFORM" == "mac" ]]; then
            sed -i '' '/server: https:\/\/192\.168\.0\.100:6443/a\
    insecure-skip-tls-verify: true
' ~/.kube/config
          else
            sed -i '/server: https:\/\/192\.168\.0\.100:6443/a\    insecure-skip-tls-verify: true' ~/.kube/config
          fi
        fi
        
        echo "✓ kubeconfig copied to ~/.kube/config"
        echo "  Server: https://192.168.0.100:6443"
        echo "  insecure-skip-tls-verify: true (for development)"
      else
        echo "⚠ WARNING: kubeconfig file not found in .ssh directory"
        echo "  Expected: ${EXPECTED_KUBECONFIG} or .ssh/kubeconfig_*"
        echo "  You may need to copy it manually or run access-k8s-from-host.sh"
      fi
    fi
  else
    sleep 5
    echo "##################################################################################"
    echo "vagrant ${EVENT}"
    echo "##################################################################################"
    vagrant ${EVENT}
  fi
  
  # Add VM IP information to info file (only after successful VM creation)
  echo "##################################################################################"
  echo "Adding VM IP information to info file..."
  echo "##################################################################################"
  
  # Ensure Vagrantfile is still correct (may have been changed)
  if [[ "${A_ENV}" == "M" ]]; then
    cp -Rf ./scripts/local/Vagrantfile Vagrantfile
  elif [[ "${A_ENV}" == "S" ]]; then
    cp -Rf ./scripts/local/Vagrantfile_slave Vagrantfile
  elif [[ "${A_ENV}" == "S2" ]]; then
    cp -Rf ./scripts/local/Vagrantfile_slave2 Vagrantfile
  fi
  
  for item in "${PROJECTS[@]}"; do
    # Check if VM exists in Vagrantfile first
    if ! grep -q "\"${item}\"" Vagrantfile 2>/dev/null && ! grep -q "'${item}'" Vagrantfile 2>/dev/null; then
      echo "⚠ Warning: ${item} not found in Vagrantfile, skipping"
      continue
    fi
    
    # Check if VM is running before trying to SSH
    VM_STATUS=$(vagrant status ${item} 2>/dev/null | grep "${item}" | grep -E "running|poweroff" || echo "")
    if [ -n "$VM_STATUS" ]; then
      echo "Getting IP for ${item}..."
      IP=$(vagrant ssh ${item} -c "ifconfig" 2>/dev/null | grep eth1 -A 1 | tail -n 1 | awk '{print $2}' || echo "")
      if [ -n "$IP" ] && [ "$IP" != "" ]; then
        echo ${item} ansible_host=${IP} ip=${IP} ansible_user=root ansible_ssh_private_key_file=/root/.ssh/tz_rsa ansible_ssh_extra_args='-o StrictHostKeyChecking=no' ansible_port=22 >> info
        echo ${IP}   ${item} >> info
        echo "✓ ${item}: ${IP}"
      else
        echo "⚠ Warning: Could not get IP for ${item}"
      fi
    else
      echo "⚠ Warning: ${item} is not running, skipping IP collection"
    fi
  done
  
  cat info
  exit 0
fi

#vagrant kube-master -c "ifconfig" | grep eth1 -A 1 | tail -n 1 | awk '{print $2}'

# NOTE: The following code is commented out as it references files that don't exist in this project
# These were likely from a different project setup and are not needed for Kubernetes cluster installation
#
# # install in docker
# export docker_user="topzone8713"
# bash /vagrant/tz-local/docker/init2.sh
#
# # remove all resources
# docker exec -it ${DOCKER_NAME} bash
# bash /vagrant/scripts/k8s_remove_all.sh
# bash /vagrant/scripts/k8s_remove_all.sh cleanTfFiles
#
# #docker container stop $(docker container ls -a -q) && docker system prune -a -f --volumes
