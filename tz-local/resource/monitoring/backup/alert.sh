#!/usr/bin/env bash

#set -x
shopt -s expand_aliases

WORKING_HOME=/var/lib/jenkins
#WORKING_HOME=/home/topzone

function prop {
  if [[ "${3}" == "" ]]; then
    grep "${2}" "${WORKING_HOME}/.aws/${1}" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'
  else
    grep "${3}" "${WORKING_HOME}/.aws/${1}" -A 10 | grep "${2}" | head -n 1 | tail -n 1 | cut -d '=' -f2 | sed 's/ //g'
  fi
}

CMD=$1
CLUSTER_NAME=$2

if [[ "${CLUSTER_NAME}" == "" ]]; then
    CLUSTER_NAME="eks-main-p"
fi
CONFIG_FILE=$(echo ${CLUSTER_NAME} | sed 's/eks-main/project/')
echo "CLUSTER_NAME: ${CLUSTER_NAME}"
echo "CONFIG_FILE: ${CONFIG_FILE}"

grafana_token=$(prop ${CONFIG_FILE} 'grafana_token')
admin_password=$(prop ${CONFIG_FILE} 'admin_password')

## to get a token
# curl -X POST -H "Content-Type: application/json" -d '{"name":"apikeycurl", "role": "Admin"}' https://admin:${admin_password}@grafana.default.${CLUSTER_NAME}.tzcorp.com/api/auth/keys
ALERTS=$(curl -X GET --insecure -H "Authorization: Bearer ${grafana_token}==" \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  https://grafana.default.${CLUSTER_NAME}.tzcorp.com/api/alerts | jq '.[].id')
ITEMS=($(echo $ALERTS | tr ' ' "\n"))
for item in "${ITEMS[@]}"; do
  echo "====================="
  echo ${item}
  curl -X POST --insecure -H "Authorization: Bearer ${grafana_token}==" \
    -H "Content-Type: application/json" -d "{\"paused\": ${CMD}}" \
    https://grafana.default.${CLUSTER_NAME}.tzcorp.com/api/alerts/${item}/pause
done
