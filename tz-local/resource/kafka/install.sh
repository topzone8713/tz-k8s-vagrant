#!/usr/bin/env bash

shopt -s expand_aliases

alias k='kubectl --kubeconfig ~/.kube/config'

k taint nodes --all node-role.kubernetes.io/master-

k create namespace kafka

k delete -f /topzone/tz-local/resource/kafka/storage-local.yaml -n kafka
k apply -f /topzone/tz-local/resource/kafka/storage-local.yaml -n kafka
k get pv -n kafka
k get pvc -n kafka
k get storageclass -n kafka

# 1. Deploy Apache Zookeeper
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm uninstall zookeeper -n kafka
helm uninstall kafka -n kafka

ZOOKEEPER_SERVICE_NAME=zookeeper
helm install ${ZOOKEEPER_SERVICE_NAME} bitnami/zookeeper \
  --set replicaCount=1 \
  --set auth.enabled=false \
  --set allowAnonymousLogin=true \
  --set volumePermissions.enabled=true \
  --set zookeeper.volumePermissions.enabled=true \
  --set global.storageClass=nfs-csi \
  --set persistence.storageClass=nfs-csi \
  -n kafka

# 2: Deploy Apache Kafka
helm install kafka bitnami/kafka \
  --set zookeeper.enabled=false \
  --set replicaCount=1 \
  --set externalZookeeper.servers=${ZOOKEEPER_SERVICE_NAME} \
  --set volumePermissions.enabled=true \
  --set zookeeper.volumePermissions.enabled=true \
  --set global.storageClass=nfs-csi \
  --set persistence.storageClass=nfs-csi \
  -n kafka

sleep 30

k get all -n kafka

k get statefulset.apps/zookeeper -n kafka -o yaml > /topzone/tz-local/resource/kafka/zookeeper.yaml
k delete statefulset.apps/zookeeper -n kafka
sudo sed -i "s|8Gi|100Mi|g" /topzone/tz-local/resource/kafka/zookeeper.yaml
k apply -f /topzone/tz-local/resource/kafka/zookeeper.yaml -n kafka

k get statefulset.apps/kafka -n kafka -o yaml > /topzone/tz-local/resource/kafka/kafka.yaml
k delete statefulset.apps/kafka -n kafka
sudo sed -i "s|8Gi|100Mi|g" /topzone/tz-local/resource/kafka/kafka.yaml
sudo sed -i "s|failureThreshold: 3|failureThreshold: 1|g" /topzone/tz-local/resource/kafka/kafka.yaml
## for access from external device
#sudo sed -i "s|INTERNAL\:PLAINTEXT,CLIENT\:PLAINTEXT|INTERNAL\:PLAINTEXT,CLIENT\:PLAINTEXT,EXTERNAL\:PLAINTEXT|g" /topzone/tz-local/resource/kafka/kafka.yaml
#sudo sed -i "s|CLIENT\://\:9092|CLIENT\://\:9092,EXTERNAL\://0.0.0.0\:9094|g" /topzone/tz-local/resource/kafka/kafka.yaml
#sudo sed -i "s|kafka-headless.kafka.svc.cluster.local\:9092|kafka-headless.kafka.svc.cluster.local\:9092,EXTERNAL\://localhost:9094|g" /topzone/tz-local/resource/kafka/kafka.yaml
k apply -f /topzone/tz-local/resource/kafka/kafka.yaml -n kafka

# run client
k delete pod/kafka-client -n kafka
k run kafka-client --restart='Never' --image docker.io/bitnami/kafka:2.6.0-debian-10-r0 -n kafka --command -- sleep infinity

# 3: Test Apache Kafka
echo '
##[ Kafka ]##########################################################

# make a producer
k exec --tty -i kafka-client -n kafka -- bash
$ kafka-console-producer.sh \
--broker-list kafka-0.kafka-headless.kafka.svc.cluster.local:9092 \
--topic quickstart-events

# make a consumer
k exec --tty -i kafka-client -n kafka -- bash
$ kafka-console-consumer.sh \
--bootstrap-server kafka.kafka.svc.cluster.local:9092 \
--from-beginning \
--topic quickstart-events

# make a topic
k exec --tty -i kafka-client -n kafka -- bash
$ kafka-topics.sh --create --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092 \
--topic quickstart-events

### with zookeeper ###
# create with zookeeper
kafka-topics.sh --create --zookeeper zookeeper.kafka.svc.cluster.local:2181 --replication-factor 1 --partitions 1 --topic sample

# list
kafka-topics.sh --list --zookeeper zookeeper.kafka.svc.cluster.local:2181
kafka-topics.sh --describe --zookeeper zookeeper.kafka.svc.cluster.local:2181 --topic sample

# Delete 1
kafka-configs.sh --zookeeper zookeeper.kafka.svc.cluster.local:2181 --alter --entity-name quickstart-events1 --entity-type topics  --add-config retention.ms=1000

# Delete 2
# kafka-topics.sh --zookeeper zookeeper.kafka.svc.cluster.local:2181 --delete --topic quickstart-events1
kubectl exec -it pod/zookeeper-0 -n kafka -- zkCli.sh
get /brokers/topics/quickstart-events
deleteall /brokers/topics/quickstart-events
delete /admin/delete_topics/quickstart-events

#######################################################################
' >> /topzone/info
cat /topzone/info

# 4: Scale Apache Kafka
#k scale statefulset.apps/zookeeper --replicas=2 -n kafka
#k scale statefulset.apps/kafka --replicas=2 -n kafka

exit 0