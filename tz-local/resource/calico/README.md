# Calico IPIP 설정 가이드

## 개요

Kubernetes 클러스터 설치 후 Calico를 IPIP 모드로 자동 구성하는 스크립트입니다.

## 문제 상황

기본 Calico 설치 시:
- VXLAN: `Never` (비활성화)
- IPIP: `Off` (비활성화)
- BGP: 설정되어 있지만 작동하지 않음
- **결과**: 크로스 노드 Pod 통신 불가, DNS 쿼리 실패

## 해결 방법

IPIP 모드를 활성화하여 크로스 노드 Pod 통신을 가능하게 합니다.

## 사용 방법

### 방법 1: Kubernetes 설치 직후 자동 설정 (권장)

**Kubernetes 클러스터 설치가 완료된 직후:**

```bash
cd ~/workspaces/tz-drillquiz/provisioning/calico
bash setup-ipip-after-k8s-install.sh
```

이 스크립트는:
1. Kubernetes 클러스터 연결 확인
2. Calico 설치 대기
3. Calico Pod 준비 대기
4. IPIP 설정 자동 적용

### 방법 2: 수동 설정

**Calico가 이미 설치되어 있는 경우:**

```bash
cd ~/workspaces/tz-drillquiz/provisioning/calico
bash configure-ipip.sh
```

## 적용되는 설정

1. **IPPool**: `ipipMode: Always`
2. **DaemonSet**: `CALICO_IPV4POOL_IPIP: Always`
3. **ConfigMap**: `calico_backend: bird` (BGP)
4. **Calico 노드 재시작**: 설정 적용

## 검증

설정 적용 후 다음 명령어로 확인:

```bash
# IPPool 확인
kubectl get ippool default-pool -o jsonpath='{.spec.ipipMode}'
# 예상 결과: Always

# DaemonSet 확인
kubectl get daemonset calico-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="CALICO_IPV4POOL_IPIP")].value}'
# 예상 결과: Always

# ConfigMap 확인
kubectl get cm calico-config -n kube-system -o jsonpath='{.data.calico_backend}'
# 예상 결과: bird

# 네트워크 테스트
kubectl run test-pod --image=busybox --rm -i --restart=Never -- nslookup kubernetes.default.svc.cluster.local
# 예상 결과: DNS 쿼리 성공
```

## 참고

- [NETWORK_STATUS_REPORT.md](../jenkins/NETWORK_STATUS_REPORT.md) - 네트워크 상태 보고서
- [DNS_DIAGNOSIS.md](../jenkins/DNS_DIAGNOSIS.md) - DNS 문제 진단 (VXLAN 문제 기록 포함)

## 주의사항

- **VXLAN은 사용하지 않음**: 이전에 VXLAN 구성 변경 시도 시 호스트 네트워크가 완전히 끊어졌습니다.
- IPIP 모드는 안전하게 작동하며 문제가 없었습니다.
