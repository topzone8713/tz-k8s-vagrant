#!/bin/bash

echo $1 > /app/aaa
VOLUME_ID=$1

echo "--------------VOLUME_ID: ${VOLUME_ID}" >> /app/aaa

mkdir -p /vault/secrets
#echo "
#AWS_ACCESS_KEY_ID=xxxx
#AWS_SECRET_ACCESS_KEY=xxxxx
#AWS_DEFAULT_REGION=ap-northeast-2
#" > /vault/secrets/aws

prop () {
    grep "${2}" "/vault/secrets/${1}" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'
}

export AWS_ACCESS_KEY_ID=$(prop 'aws' 'AWS_ACCESS_KEY_ID')
export AWS_SECRET_ACCESS_KEY=$(prop 'aws' 'AWS_SECRET_ACCESS_KEY')
export AWS_DEFAULT_REGION=$(prop 'aws' 'AWS_DEFAULT_REGION')
#VOLUME_ID=vol-0ccc1a959af735003
DESC="k8s mysql volume snapshot"

echo "--------------${AWS_ACCESS_KEY_ID}" >> /app/aaa
echo "--------------${AWS_SECRET_ACCESS_KEY}" >> /app/aaa
echo "--------------${AWS_DEFAULT_REGION}" >> /app/aaa
echo "--------------${VOLUME_ID}" >> /app/aaa

echo aws ec2 create-snapshot \
  --volume-id ${VOLUME_ID} \
  --description "${DESC}" >> /app/aaa

sleep 60

aws ec2 create-snapshot \
  --volume-id ${VOLUME_ID} \
  --description "${DESC}"

sleep 10

