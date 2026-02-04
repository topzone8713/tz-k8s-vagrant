# Prometheus로 알림 받기

``` 
두가지 방법이 있습니다.
1. grafana에서 정의 (팀에서 직접 관리 가능)
2. alertmanager에서 바로 정의 (DevOps가 관리함)
``` 

## 0. 모니터링할 http url 등록
``` 
이것은 두 방법 모두 DevOps가 일단 적용해야 합니다. Metric을 수집할 소스를 등록하는 과정입니다.

tz-eks-main/tz-local/resource/monitoring/prometheus/prometheus-values.yaml
      - job_name: 'tz-blackbox-exporter'
        metrics_path: /probe
        params:
          module: [http_2xx]
        static_configs:
          - targets:
            - http://tz-sample-app.tz-production.svc
            - http://tz-sample-app.tz-development.svc
```

## 1. grafana에서 정의 (팀에서 직접 관리 가능)
```
  grafana에서 할당된 팀별 폴더에서 Dashboard 및 pannel을 정의하면서 alert을 정의할 수 있습니다.
  예시)
  https://grafana.default.eks-main.k8s_domain/d/v1XzetqGz/devops-demo?orgId=1

  "0. 모니터링할 http url 등록"에서 수집된 url별로, http, https의 에러 코드별로 쿼리하고
  alert 정의를 통해서 담당자에게 메일 발송을 정의합니다.

```

## 2. alertmanager에서 바로 정의 (DevOps가 관리함)
```
메시지를 받을 수신자 지정 
tz-eks-main/tz-local/resource/monitoring/prometheus/alertmanager.values

  route:
    receiver: 'k8s-admin'
    repeat_interval: 5m
    routes:
    - receiver: 'dev_mail'
      match:
        instance: http://tz-sample-app.tz-development.svc
    - receiver: 'prod_mail'
      match:
        instance: http://tz-sample-app.tz-production.svc
    - receiver: 'dev_mail'
      match:
        namespace: 'tz-development'
  receivers:
  - name: 'k8s-admin'
    email_configs:
    - to: doohee@${k8s_domain}
  - name: 'dev_mail'
    email_configs:
    - to: doohee.hong@tz.com
  - name: 'prod_mail'
    email_configs:
    - to: topzone8713@gmail.com
```

## 룰 적용 (DevOps가 수행)
```
bash /vagrant/tz-local/resource/monitoring/prometheus/update.sh

update.sh에는 아래의 작업들이 포함되어 있습니다.
export NS=monitoring
helm upgrade --reuse-values -f alertmanager.values prometheus prometheus-community/kube-prometheus-stack -n ${NS}
kubectl rollout restart statefulset.apps/prometheus-alertmanager -n ${NS}
sleep 20

helm upgrade --reuse-values -f prometheus-values.yaml prometheus prometheus-community/kube-prometheus-stack -n ${NS}
kubectl rollout restart statefulset.apps/prometheus-prometheus-kube-prometheus-prometheus -n ${NS}
sleep 20
```

## Loki: 며칠 지나면 CrashLoopBackOff / read-only file system

**원인**  
Loki가 스토리지를 **EmptyDir**로 쓰고 있으면, WAL/청크가 쌓여 며칠 뒤 디스크가 가득 찬다.  
이때 쓰기 실패가 "read-only file system"처럼 나오고, 재시작 probe 실패 → CrashLoopBackOff가 반복된다.  
재시작하면 EmptyDir이 비워져서 잠시 정상이다가, 다시 쌓이면 같은 현상이 반복된다.

**해결**  
스토리지를 **PVC**로 바꿔야 한다.

- **신규 설치**: `install.sh`가 `loki-stack-values.yaml`(PVC 10Gi, storageClassName: nfs-client)을 사용하므로, 그대로 설치하면 PVC로 올라간다.
- **이미 EmptyDir로 떠 있는 클러스터**  
  - StatefulSet에는 **이미 만든 뒤에는 volumeClaimTemplate 추가가 불가**하다.  
  - 따라서 **StatefulSet 삭제 후 재설치**가 필요하다.  
    1. `kubectl delete statefulset loki -n monitoring`  
    2. `cd /vagrant/tz-local/resource/monitoring && bash install.sh` (또는 Loki 설치 부분만 helm upgrade --install loki ... -f loki-stack-values.yaml)  
  - 재설치 후 Pod는 새 PVC에 붙어 올라가고, retention(loki_storage.yaml 336h)에 따라 오래된 데이터는 정리된다.



