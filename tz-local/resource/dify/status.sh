#!/usr/bin/env bash
# Dify 설치 상태 모니터링 (dify 네임스페이스 Pod/PVC/SVC/Ingress)
# 사용: ./status.sh [watch] — watch 생략 시 1회 출력, 있으면 2초 간격 갱신

NS="${DIFY_NS:-dify}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
WATCH="${1:-}"

kubectl --kubeconfig "${KUBECONFIG}" get pods,svc,pvc,ingress -n "${NS}" 2>/dev/null || {
  echo "Namespace ${NS} 없음 또는 kubectl 접근 실패. KUBECONFIG 확인."
  exit 1
}

if [[ "$WATCH" == "watch" ]] || [[ "$WATCH" == "-w" ]]; then
  echo ""
  echo "--- Pod 상태 실시간 갱신 (Ctrl+C 종료) ---"
  kubectl --kubeconfig "${KUBECONFIG}" get pods -n "${NS}" -w
fi
