#https://aws.amazon.com/ko/premiumsupport/knowledge-center/eks-persistent-storage/

cd /topzone/tz-local/resource/mysql

AWS_REGION=$(prop 'config' 'region')
k8s_project=$(prop 'project' 'project')
aws_account_id=$(aws sts get-caller-identity --query Account --output text)
NS=devops-dev

echo "########################################################################"
echo "Get current PV_ID, VOLUME_ID and SUBNET_ID"
echo "########################################################################"
PV_ID=$(kubectl get pv | grep mysql | awk '{print $1}')
echo ${PV_ID}
TMP=$(kubectl describe pv ${PV_ID} | grep VolumeID: | awk '{print $2}')
echo ${TMP}
SUBNET_ID=$(echo ${TMP} | rev | cut -d '/' -f '2' | rev)
echo ${SUBNET_ID}
VOLUME_ID=$(echo ${TMP} | rev | cut -d '/' -f '1' | rev)
echo ${VOLUME_ID}

echo "########################################################################"
echo "Make a snapshot from current"
echo "########################################################################"
SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --volume-id ${VOLUME_ID} \
  --description "k8s mysql volume snapshot" | grep SnapshotId | awk -F\" '{print $4}')
echo $SNAPSHOT_ID

INC_CNT=0
MAX_CNT=100
while true; do
  sleep 5
  echo "checking... ${SNAPSHOT_ID}"
  if [[ $INC_CNT == $MAX_CNT ]]; then
    break
  fi
  if [[ $STATUS == "completed" ]]; then
    break
  fi
  let "INC_CNT=INC_CNT+1"
  STATUS=$(aws ec2 describe-snapshots \
    --snapshot-ids ${SNAPSHOT_ID} | grep State | awk -F\" '{print $4}')
done

#aws ec2 copy-snapshot \
#    --region us-east-1 \
#    --source-region us-west-2 \
#    --source-snapshot-id ${SNAPSHOT_ID} \
#    --description "This is my copied snapshot."

echo "########################################################################"
echo "Make a volume from the snapshot"
echo "########################################################################"
NEW_VOLUME_ID=$(aws ec2 create-volume \
    --region ${AWS_REGION} \
    --availability-zone ${SUBNET_ID} \
    --volume-type nfs-client \
    --snapshot-id ${SNAPSHOT_ID} \
    --size 1 | grep VolumeId | awk '{print $2}' | sed 's/\"//g;s/\,//g')
#aws ec2 delete-volume --volume-id ${NEW_VOLUME_ID}
echo ${NEW_VOLUME_ID}

INC_CNT=0
MAX_CNT=100
while true; do
  sleep 5
  echo "checking... ${NEW_VOLUME_ID}"
  if [[ $INC_CNT == $MAX_CNT ]]; then
    break
  fi
  if [[ $STATUS == "ok" ]]; then
    break
  fi
  let "INC_CNT=INC_CNT+1"
  STATUS=$(aws ec2 describe-volume-status --volume-ids ${NEW_VOLUME_ID} | \
    grep Status | awk -F\" '{print $4}' | tail -n 1)
done

echo "########################################################################"
echo "Make a new PV and PVC"
echo "########################################################################"
cp -Rf claim.yaml claim.yaml_bak
sed -i "s/SUBNET_ID/${SUBNET_ID}/g" claim.yaml_bak
sed -i "s/VOLUME_ID/${NEW_VOLUME_ID}/g" claim.yaml_bak

k get deployment mysql -n ${NS} -o json \
    | jq '.spec.template.spec.volumes[0].persistentVolumeClaim.claimName = "tmp"' \
    | kubectl replace -f -

kubectl delete -f claim.yaml_bak -R -n ${NS}
kubectl apply -f claim.yaml_bak -R -n ${NS}

echo "########################################################################"
echo "Replace PCV for mysql"
echo "########################################################################"
k get deployment mysql -n ${NS} -o json \
    | jq '.spec.template.spec.volumes[0].persistentVolumeClaim.claimName = "mysql2"' \
    | kubectl replace -f -
#k patch deployment mysql -n ${NS} -p '{"spec": {"volumes": {"persistentVolumeClaim": {"claimName": "mysql"}}}}'

sleep 30

MYSQL_ROOT_PASSWORD=$(kubectl get secret --namespace ${NS} mysql -o jsonpath="{.data.mysql-root-password}" | base64 --decode; echo)
MYSQL_HOST=$(kubectl get svc mysql -n ${NS} | tail -n 1 | awk '{print $4}')
MYSQL_PORT=3306
mysql -h ${MYSQL_HOST} -P ${MYSQL_PORT} --user=root -p${MYSQL_ROOT_PASSWORD} -e "SHOW databases;"


