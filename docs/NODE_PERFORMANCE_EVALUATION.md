# Kubernetes 노드 성능 평가 가이드

## 개요

이 문서는 Kubernetes 클러스터의 노드 성능을 평가하는 방법을 설명합니다. kube-node-2를 예시로 사용합니다.

## 성능 평가 항목

### 1. 노드 기본 정보

**명령어:**
```bash
kubectl get node <node-name> -o wide
```

**확인 사항:**
- STATUS: Ready 여부
- VERSION: Kubernetes 버전
- INTERNAL-IP: 노드 IP 주소
- OS-IMAGE: 운영체제 정보
- CONTAINER-RUNTIME: 컨테이너 런타임 버전

**예시 (kube-node-2):**
```
NAME          STATUS   ROLES    AGE   VERSION   INTERNAL-IP      EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION       CONTAINER-RUNTIME
kube-node-2   Ready    <none>   18d   v1.30.6   192.168.86.102   <none>        Ubuntu 22.04.5 LTS   5.15.0-160-generic   containerd://1.7.23
```

### 2. 노드 리소스 용량 및 할당량

**명령어:**
```bash
kubectl describe node <node-name> | grep -A 30 "Capacity:\|Allocatable:\|Allocated resources:"
```

**확인 사항:**

#### Capacity (전체 용량)
- **CPU**: 전체 CPU 코어 수
- **Memory**: 전체 메모리 용량
- **ephemeral-storage**: 임시 스토리지 용량
- **pods**: 최대 Pod 수

#### Allocatable (할당 가능한 리소스)
- 시스템 리소스(OS, kubelet 등)를 제외한 실제 사용 가능한 리소스
- Capacity보다 약간 적음 (시스템 예약분)

#### Allocated resources (현재 할당된 리소스)
- **Requests**: Pod들이 요청한 리소스
- **Limits**: Pod들의 최대 리소스 제한
- **사용률 계산**: (Requests / Allocatable) × 100

**예시 (kube-node-2):**
```
Capacity:
  cpu:                2
  memory:             4003732Ki (~3.8GB)
  ephemeral-storage:  31811408Ki (~30GB)
  pods:               110

Allocatable:
  cpu:                1900m (1.9 cores)
  memory:             3639188Ki (~3.5GB)
  ephemeral-storage:  29317393565 (~27GB)
  pods:               110

Allocated resources:
  Resource           Requests        Limits
  --------           --------        ------
  cpu                555m (29%)      2500m (131%)
  memory             732Mi (20%)     4.5Gi (129%)
```

**성능 평가:**
- ✅ **양호**: CPU 사용률 < 70%, Memory 사용률 < 80%
- ⚠️ **주의**: CPU 사용률 70-90%, Memory 사용률 80-90%
- ❌ **위험**: CPU 사용률 > 90%, Memory 사용률 > 90%

**kube-node-2 평가:**
- CPU Requests: 29% (양호)
- CPU Limits: 131% (과다 할당, 정상 - Limits는 최대값)
- Memory Requests: 20% (양호)
- Memory Limits: 129% (과다 할당, 정상)

### 3. 노드 상태 (Conditions)

**명령어:**
```bash
kubectl describe node <node-name> | grep -E "Conditions:|MemoryPressure|DiskPressure|PIDPressure|Ready"
```

**확인 사항:**
- **Ready**: 노드가 Pod를 수락할 수 있는지 여부
- **MemoryPressure**: 메모리 압박 상태
- **DiskPressure**: 디스크 압박 상태
- **PIDPressure**: PID 압박 상태

**예시 (kube-node-2):**
```
Conditions:
  MemoryPressure       False   ✅ 정상
  DiskPressure         False   ✅ 정상
  PIDPressure          False   ✅ 정상
  Ready                True    ✅ 정상
```

**성능 평가:**
- ✅ **양호**: 모든 조건이 False/True (정상)
- ❌ **문제**: MemoryPressure, DiskPressure, PIDPressure 중 하나라도 True

### 4. 실행 중인 Pod 현황

**명령어:**
```bash
# 노드에 실행 중인 모든 Pod
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=<node-name>

# Pod 수 통계
kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name> -o json | jq -r '[.items[] | select(.status.phase == "Running")] | length'
```

**확인 사항:**
- 실행 중인 Pod 수
- 비정상 상태 Pod (Pending, CrashLoopBackOff, Error 등)
- 재시작 횟수가 많은 Pod

**예시 (kube-node-2):**
- 총 Pod 수: 10개
- Running: 9개
- Completed: 1개 (external-secrets init job)

**성능 평가:**
- ✅ **양호**: 대부분의 Pod가 Running 상태
- ⚠️ **주의**: 일부 Pod가 Pending 또는 CrashLoopBackOff
- ❌ **문제**: 많은 Pod가 비정상 상태

### 5. 리소스 사용량 (Metrics API)

**명령어:**
```bash
# 노드 리소스 사용량
kubectl top node <node-name>

# Pod 리소스 사용량
kubectl top pods --all-namespaces --field-selector spec.nodeName=<node-name>
```

**주의**: Metrics API가 설치되어 있어야 합니다 (metrics-server 또는 Prometheus).

**확인 사항:**
- 실제 CPU 사용량 (Requests와 비교)
- 실제 Memory 사용량 (Requests와 비교)

**예시:**
```
NAME          CPU(cores)   MEMORY(bytes)
kube-node-2   450m         1.2Gi
```

**성능 평가:**
- 실제 사용량이 Requests보다 낮으면: ✅ 효율적
- 실제 사용량이 Requests와 비슷하면: ✅ 적절
- 실제 사용량이 Limits에 근접하면: ⚠️ 리소스 부족 가능

### 6. 시스템 리소스 (VM 레벨)

**명령어:**
```bash
# VM에 직접 접속
ssh root@<node-ip>

# 메모리 사용량
free -h

# CPU 코어 수
nproc

# 디스크 사용량
df -h /

# 시스템 부하
uptime
```

**확인 사항:**
- 실제 메모리 사용률
- 디스크 사용률
- 시스템 부하 평균 (load average)

**성능 평가:**
- Load average < CPU 코어 수: ✅ 정상
- Load average ≈ CPU 코어 수: ⚠️ 부하 높음
- Load average > CPU 코어 수: ❌ 과부하

### 7. Pod 재시작 및 이벤트

**명령어:**
```bash
# 재시작 횟수가 많은 Pod 찾기
kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name> -o json | \
  jq -r '.items[] | select(.status.containerStatuses[]?.restartCount > 5) | 
  .metadata.namespace + "/" + .metadata.name + ": " + 
  (.status.containerStatuses[] | select(.restartCount > 5) | 
  .name + " restartCount: " + (.restartCount | tostring))'

# 노드 관련 이벤트
kubectl get events --all-namespaces --field-selector involvedObject.name=<node-name> --sort-by=".lastTimestamp" | tail -20
```

**확인 사항:**
- 재시작 횟수가 많은 Pod (5회 이상)
- 노드 관련 경고/오류 이벤트

**성능 평가:**
- 재시작이 없거나 적음: ✅ 정상
- 일부 Pod만 재시작: ⚠️ 해당 Pod 문제 가능
- 많은 Pod가 재시작: ❌ 노드 문제 가능

## kube-node-2 성능 평가 결과

### 현재 상태 요약

**기본 정보:**
- **상태**: Ready ✅
- **운영 시간**: 18일
- **Kubernetes 버전**: v1.30.6
- **OS**: Ubuntu 22.04.5 LTS

**리소스 용량:**
- **CPU**: 2 cores (Allocatable: 1.9 cores)
- **Memory**: ~3.8GB (Allocatable: ~3.5GB)
- **Storage**: ~30GB (Allocatable: ~27GB)
- **Max Pods**: 110

**리소스 사용률:**
- **CPU Requests**: 555m (29% of Allocatable) ✅ 양호
- **CPU Limits**: 2500m (131% - 과다 할당, 정상)
- **Memory Requests**: 732Mi (20% of Allocatable) ✅ 양호
- **Memory Limits**: 4.5Gi (129% - 과다 할당, 정상)

**노드 상태:**
- **Ready**: True ✅
- **MemoryPressure**: False ✅
- **DiskPressure**: False ✅
- **PIDPressure**: False ✅

**Pod 현황:**
- **총 Pod 수**: 10개
- **Running**: 9개 ✅
- **Completed**: 1개 (정상 - init job)
- **비정상 Pod**: 없음 ✅

**주요 Pod:**
- jenkins-0: Jenkins 서버 (CPU: 50m, Memory: 256Mi)
- alertmanager: 모니터링 (CPU: 200m, Memory: 250Mi)
- calico-node: 네트워크 플러그인 (CPU: 150m, Memory: 64Mi)
- 기타 시스템 Pod들

### 성능 평가 종합

| 항목 | 상태 | 평가 |
|------|------|------|
| **노드 상태** | Ready | ✅ 정상 |
| **리소스 사용률** | CPU 29%, Memory 20% | ✅ 양호 (여유 있음) |
| **노드 압박 상태** | 모두 False | ✅ 정상 |
| **Pod 상태** | 대부분 Running | ✅ 정상 |
| **재시작 이슈** | 일부 Pod 재시작 (정상 범위) | ✅ 정상 |

**종합 평가: ✅ 양호**

kube-node-2는 현재 정상적으로 작동하고 있으며, 리소스 사용률이 낮아 여유가 있습니다. 추가 Pod를 스케줄링할 수 있는 여유가 충분합니다.

## 성능 모니터링 명령어 모음

### 빠른 상태 확인
```bash
# 노드 기본 정보
kubectl get node <node-name> -o wide

# 노드 리소스 요약
kubectl describe node <node-name> | grep -A 5 "Allocated resources:"

# 노드 상태
kubectl describe node <node-name> | grep -E "Conditions:|Ready"
```

### 상세 분석
```bash
# 전체 리소스 정보
kubectl describe node <node-name>

# 실행 중인 Pod 목록
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=<node-name>

# 리소스 사용량 (Metrics API 필요)
kubectl top node <node-name>
kubectl top pods --all-namespaces --field-selector spec.nodeName=<node-name>
```

### 문제 진단
```bash
# 비정상 Pod 찾기
kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name> | grep -v Running

# 재시작 횟수 확인
kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name> -o wide | awk '{print $4}' | sort | uniq -c

# 노드 이벤트 확인
kubectl get events --all-namespaces --field-selector involvedObject.name=<node-name> --sort-by=".lastTimestamp" | tail -20
```

## 성능 개선 권장사항

### 리소스 사용률이 높은 경우

1. **Pod 리소스 요청 최적화**
   - 실제 사용량을 모니터링하여 Requests를 조정
   - 불필요하게 높은 Limits 감소

2. **Pod 분산**
   - 다른 노드로 Pod 이동 (taint/toleration 사용)
   - 노드 선택기(nodeSelector) 조정

3. **노드 스케일 아웃**
   - 추가 노드 추가
   - 클러스터 자동 스케일링 고려

### 메모리 압박이 있는 경우

1. **메모리 사용량 분석**
   ```bash
   kubectl top pods --all-namespaces --field-selector spec.nodeName=<node-name> --sort-by=memory
   ```

2. **메모리 제한 조정**
   - Pod의 memory limits 조정
   - 메모리 누수 가능성 있는 Pod 확인

3. **디스크 스왑 확인**
   ```bash
   ssh root@<node-ip> 'free -h'
   ```

### CPU 압박이 있는 경우

1. **CPU 사용량 분석**
   ```bash
   kubectl top pods --all-namespaces --field-selector spec.nodeName=<node-name> --sort-by=cpu
   ```

2. **CPU 제한 조정**
   - CPU-intensive Pod의 limits 조정
   - CPU 요청 최적화

## 참고 자료

- [Kubernetes Node Resources](https://kubernetes.io/docs/concepts/architecture/nodes/)
- [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Node Conditions](https://kubernetes.io/docs/concepts/architecture/nodes/#condition)

---

## 작성일

2026-01-23
