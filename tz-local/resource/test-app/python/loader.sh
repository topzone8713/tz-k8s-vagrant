#!/usr/bin/env bash

#set -x

INC_CNT=0
MAX_CNT=50
while true; do
  sleep 1
  if [[ $INC_CNT == $MAX_CNT ]]; then
    break
  fi
  let "INC_CNT=INC_CNT+1"

  echo curl -d "watch_ids=kVQEW0SNFqE" -X POST http://98.234.161.130:30007/crawl
  curl -d "watch_ids=kVQEW0SNFqE" -X POST http://98.234.161.130:30007/crawl
done

exit 0

k get deployment tz-py-crawler -o wide

k apply -f /vagrant/tz-local/resource/test-app/python/tz-py-crawler_autoscale.yaml

https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#autoscale
k describe nodes
k autoscale deployment tz-py-crawler --cpu-percent 20 --min 1 --max 10
k delete hpa tz-py-crawler

k scale --replicas=5 deployment tz-py-crawler
