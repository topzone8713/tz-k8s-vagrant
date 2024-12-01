#!/usr/bin/env bash

#https://www.vladionescu.me/posts/eks-dns/
#https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
#https://medium.com/@danielmller_75561/performance-issues-with-rds-aurora-on-eks-due-to-coredns-defaults-5fb2166366c9

cd /topzone/tz-local/resource/local-dns

kubectl scale deployment/coredns \
    --namespace kube-system \
    --current-replicas=2 \
    --replicas=10

kubedns=$(kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP})
domain=cluster.local
localdns=169.254.20.10
cp nodelocaldns.yaml nodelocaldns.yaml_bak
sed -i "s|__PILLAR__LOCAL__DNS__|${localdns}|g; s|__PILLAR__DNS__DOMAIN__|${domain}|g; s|__PILLAR__DNS__SERVER__|${kubedns}|g" nodelocaldns.yaml_bak

kubectl apply -f nodelocaldns.yaml_bak


#prometheus-kube-prometheus-operator.monitoring.svc.cluster.local



