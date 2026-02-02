#!/bin/bash
# Kubernetes 설치 후 Calico IPIP 자동 설정 스크립트
# Kubernetes 클러스터가 설치된 직후에 실행하여 Calico를 IPIP 모드로 구성
#
# 사용법: 
#   Kubernetes 설치 완료 후: bash setup-ipip-after-k8s-install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURE_IPIP_SCRIPT="$SCRIPT_DIR/configure-ipip.sh"

echo "=========================================="
echo "Kubernetes 설치 후 Calico IPIP 자동 설정"
echo "=========================================="
echo ""

# KUBECONFIG 파일 확인
if [ -z "$KUBECONFIG_FILE" ]; then
  if [ -f ~/.kube/my-ubuntu.config ]; then
    KUBECONFIG_FILE=~/.kube/my-ubuntu.config
  elif [ -f ~/.kube/config ]; then
    KUBECONFIG_FILE=~/.kube/config
  else
    echo "Error: No kubeconfig file found (~/.kube/my-ubuntu.config or ~/.kube/config)"
    echo ""
    echo "Kubernetes 클러스터가 설치되었는지 확인하세요."
    echo "kubeconfig 파일이 ~/.kube/config에 있어야 합니다."
    exit 1
  fi
fi

export KUBECONFIG="${KUBECONFIG_FILE}"

# 1. Kubernetes 클러스터 확인
echo "1. Kubernetes 클러스터 확인..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "Error: Kubernetes 클러스터에 연결할 수 없습니다"
    echo "   KUBECONFIG: $KUBECONFIG_FILE"
    exit 1
fi

NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODES" -eq 0 ]; then
    echo "Error: 노드를 찾을 수 없습니다"
    exit 1
fi

echo "   ✓ 클러스터 연결 확인됨"
echo "   ✓ 노드 수: $NODES"
echo ""

# 2. Calico 설치 대기
echo "2. Calico 설치 대기..."
echo "   Calico가 설치될 때까지 대기 중 (최대 5분)..."

MAX_WAIT=300  # 5분
ELAPSED=0
CHECK_INTERVAL=10

while [ $ELAPSED -lt $MAX_WAIT ]; do
    if kubectl get daemonset calico-node -n kube-system >/dev/null 2>&1; then
        echo "   ✓ Calico 설치 확인됨"
        break
    fi
    
    echo "   대기 중... ($ELAPSED초 경과)"
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "   ⚠ Warning: Calico가 아직 설치되지 않았습니다"
    echo "   Calico 설치를 기다리거나 수동으로 설치하세요"
    exit 1
fi

# 3. Calico Pod 준비 대기
echo ""
echo "3. Calico Pod 준비 대기..."
echo "   Calico Pod가 Running 상태가 될 때까지 대기 중 (최대 5분)..."

if kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s 2>/dev/null; then
    echo "   ✓ 모든 Calico Pod가 준비되었습니다"
else
    echo "   ⚠ Warning: 일부 Calico Pod가 아직 준비되지 않았습니다"
    echo "   현재 상태:"
    kubectl get pods -n kube-system | grep calico-node | head -5
    echo ""
    echo "   계속 진행하시겠습니까? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo ""

# 4. IPIP 설정 적용
echo "4. Calico IPIP 설정 적용..."
echo ""

if [ -f "$CONFIGURE_IPIP_SCRIPT" ]; then
    # set -e를 일시적으로 비활성화하여 에러 처리를 상위 스크립트에 위임
    set +e
    bash "$CONFIGURE_IPIP_SCRIPT"
    CONFIGURE_EXIT_CODE=$?
    set -e
    
    if [ $CONFIGURE_EXIT_CODE -ne 0 ]; then
        echo "   ⚠ Warning: configure-ipip.sh 실행 실패 (exit code: $CONFIGURE_EXIT_CODE)"
        echo "   수동으로 IPIP 설정을 적용하세요:"
        echo ""
        echo "   kubectl patch ippool default-pool --type merge -p '{\"spec\":{\"ipipMode\":\"Always\"}}'"
        echo "   kubectl set env daemonset/calico-node -n kube-system CALICO_IPV4POOL_IPIP=Always"
        echo "   kubectl patch cm calico-config -n kube-system --type merge -p '{\"data\":{\"calico_backend\":\"bird\"}}'"
        echo "   kubectl rollout restart daemonset/calico-node -n kube-system"
        exit $CONFIGURE_EXIT_CODE
    fi
else
    echo "   ⚠ Warning: configure-ipip.sh를 찾을 수 없습니다"
    echo "   수동으로 IPIP 설정을 적용하세요:"
    echo ""
    echo "   kubectl patch ippool default-pool --type merge -p '{\"spec\":{\"ipipMode\":\"Always\"}}'"
    echo "   kubectl set env daemonset/calico-node -n kube-system CALICO_IPV4POOL_IPIP=Always"
    echo "   kubectl patch cm calico-config -n kube-system --type merge -p '{\"data\":{\"calico_backend\":\"bird\"}}'"
    echo "   kubectl rollout restart daemonset/calico-node -n kube-system"
    exit 1
fi

echo ""
echo "=========================================="
echo "완료"
echo "=========================================="
echo ""
echo "Calico IPIP 설정이 완료되었습니다."
echo ""
echo "네트워크 테스트:"
echo "  kubectl run test-pod --image=busybox --rm -i --restart=Never -- nslookup kubernetes.default.svc.cluster.local"
echo ""
