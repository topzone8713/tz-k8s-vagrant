#!/bin/bash
# Calico IPIP 설정 스크립트
# Kubernetes 설치 후 Calico를 IPIP 모드로 자동 구성
#
# 사용법: bash configure-ipip.sh

set -e

# KUBECONFIG 파일 확인
if [ -z "$KUBECONFIG_FILE" ]; then
  if [ -f ~/.kube/my-ubuntu.config ]; then
    KUBECONFIG_FILE=~/.kube/my-ubuntu.config
  elif [ -f ~/.kube/config ]; then
    KUBECONFIG_FILE=~/.kube/config
  else
    echo "Error: No kubeconfig file found (~/.kube/my-ubuntu.config or ~/.kube/config)"
    exit 1
  fi
fi

export KUBECONFIG="${KUBECONFIG_FILE}"

echo "=========================================="
echo "Calico IPIP 설정 스크립트"
echo "=========================================="
echo "KUBECONFIG: $KUBECONFIG_FILE"
echo ""

# 1. Kubernetes 클러스터 연결 확인
echo "1. Kubernetes 클러스터 연결 확인..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "Error: Kubernetes 클러스터에 연결할 수 없습니다"
    exit 1
fi

NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODES" -eq 0 ]; then
    echo "Error: 노드를 찾을 수 없습니다"
    exit 1
fi

echo "   ✓ 클러스터 연결 확인됨 ($NODES개 노드)"
echo ""

# 2. Calico 설치 확인
echo "2. Calico 설치 확인..."
if ! kubectl get daemonset calico-node -n kube-system >/dev/null 2>&1; then
    echo "Error: Calico가 설치되어 있지 않습니다"
    echo "   먼저 Calico를 설치하세요"
    exit 1
fi

echo "   ✓ Calico 설치 확인됨"
echo ""

# 3. IPPool 확인 및 수정
echo "3. IPPool 설정..."

# IPPool 이름 확인
IPPOOL_NAME=$(kubectl get ippool -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$IPPOOL_NAME" ]; then
    echo "   ⚠ Warning: IPPool을 찾을 수 없습니다"
    echo "   Calico가 아직 완전히 초기화되지 않았을 수 있습니다"
    echo "   30초 대기 후 재시도..."
    sleep 30
    IPPOOL_NAME=$(kubectl get ippool -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$IPPOOL_NAME" ]; then
        echo "   ❌ Error: IPPool을 찾을 수 없습니다"
        exit 1
    fi
fi

echo "   IPPool 이름: $IPPOOL_NAME"

# 현재 IPPool 설정 확인
CURRENT_IPIP=$(kubectl get ippool "$IPPOOL_NAME" -o jsonpath='{.spec.ipipMode}' 2>/dev/null || echo "없음")
echo "   현재 ipipMode: $CURRENT_IPIP"

if [ "$CURRENT_IPIP" = "Always" ]; then
    echo "   ✓ IPPool이 이미 Always 모드로 설정되어 있습니다"
else
    echo "   IPPool의 ipipMode를 Always로 변경 중..."
    kubectl patch ippool "$IPPOOL_NAME" --type merge -p '{"spec":{"ipipMode":"Always"}}'
    echo "   ✓ IPPool 업데이트 완료"
fi
echo ""

# 4. DaemonSet 환경 변수 수정
echo "4. DaemonSet 환경 변수 설정..."

CURRENT_DAEMONSET_IPIP=$(kubectl get daemonset calico-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="CALICO_IPV4POOL_IPIP")].value}' 2>/dev/null || echo "없음")
echo "   현재 CALICO_IPV4POOL_IPIP: $CURRENT_DAEMONSET_IPIP"

if [ "$CURRENT_DAEMONSET_IPIP" = "Always" ]; then
    echo "   ✓ DaemonSet이 이미 Always 모드로 설정되어 있습니다"
else
    echo "   DaemonSet의 CALICO_IPV4POOL_IPIP를 Always로 변경 중..."
    kubectl set env daemonset/calico-node -n kube-system CALICO_IPV4POOL_IPIP=Always
    echo "   ✓ DaemonSet 업데이트 완료"
fi
echo ""

# 5. Calico Backend 설정 (BGP)
echo "5. Calico Backend 설정..."

CURRENT_BACKEND=$(kubectl get cm calico-config -n kube-system -o jsonpath='{.data.calico_backend}' 2>/dev/null || echo "없음")
echo "   현재 calico_backend: $CURRENT_BACKEND"

if [ "$CURRENT_BACKEND" = "bird" ]; then
    echo "   ✓ Backend가 이미 bird (BGP)로 설정되어 있습니다"
else
    echo "   Backend를 bird (BGP)로 변경 중..."
    kubectl patch cm calico-config -n kube-system --type merge -p '{"data":{"calico_backend":"bird"}}'
    echo "   ✓ Backend 업데이트 완료"
fi
echo ""

# 6. Calico 노드 재시작
echo "6. Calico 노드 재시작..."
kubectl rollout restart daemonset/calico-node -n kube-system
echo "   ✓ Calico 노드 재시작 중..."
echo ""

# 7. Calico Pod 재시작 대기
echo "7. Calico Pod 재시작 대기..."
echo "   최대 120초 대기 중..."

if kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=120s 2>/dev/null; then
    echo "   ✓ 모든 Calico Pod가 준비되었습니다"
else
    echo "   ⚠ Warning: 일부 Calico Pod가 아직 준비되지 않았습니다"
    echo "   현재 상태:"
    kubectl get pods -n kube-system | grep calico-node
fi
echo ""

# 8. 설정 확인
echo "8. 최종 설정 확인..."
echo ""

FINAL_IPIP=$(kubectl get ippool "$IPPOOL_NAME" -o jsonpath='{.spec.ipipMode}' 2>/dev/null || echo "없음")
FINAL_DAEMONSET_IPIP=$(kubectl get daemonset calico-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="CALICO_IPV4POOL_IPIP")].value}' 2>/dev/null || echo "없음")
FINAL_BACKEND=$(kubectl get cm calico-config -n kube-system -o jsonpath='{.data.calico_backend}' 2>/dev/null || echo "없음")

echo "   IPPool ipipMode: $FINAL_IPIP"
echo "   DaemonSet CALICO_IPV4POOL_IPIP: $FINAL_DAEMONSET_IPIP"
echo "   ConfigMap calico_backend: $FINAL_BACKEND"
echo ""

# 9. 네트워크 테스트 (선택사항)
echo "9. 네트워크 테스트..."
echo "   잠시 대기 후 테스트 (30초)..."
sleep 30

# Pod 간 통신 테스트
echo "   Pod 간 통신 테스트..."
if kubectl run test-ipip-network --image=busybox --rm -i --restart=Never -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
    echo "   ✓ DNS 쿼리 성공"
else
    echo "   ⚠ DNS 쿼리 실패 (Calico가 아직 완전히 준비되지 않았을 수 있음)"
fi
echo ""

echo "=========================================="
echo "완료"
echo "=========================================="
echo ""
echo "Calico IPIP 설정이 완료되었습니다."
echo ""
echo "네트워크 상태 확인:"
echo "  kubectl get pods -n kube-system | grep calico-node"
echo "  kubectl get ippool"
echo ""
echo "라우팅 테이블 확인 (VM에서):"
echo "  ip route show | grep 10.233"
echo ""
echo "Pod 간 통신 테스트:"
echo "  kubectl run test-pod --image=busybox --rm -i --restart=Never -- nslookup kubernetes.default.svc.cluster.local"
echo ""
