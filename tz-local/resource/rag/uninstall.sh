#!/usr/bin/env bash
# RAG 스택 + Dify 전체 삭제 (install.sh 역순)
# 사용: ./uninstall.sh
#   - Dify: Ingress, Helm, namespace dify 제거
#   - RAG: Ingress, CronJob/Job, Backend/Frontend, Qdrant(Helm), namespace rag 제거

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ -f /root/.bashrc ]]; then
  source /root/.bashrc
fi
function prop {
  key="${2}="
  file="/root/.k8s/${1}"
  if [[ ! -f "$file" ]]; then echo ""; return; fi
  rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g')
  [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g')
  echo "$rslt" | tr -d '\n' | tr -d '\r'
}

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
alias k="kubectl --kubeconfig ${KUBECONFIG}"

k8s_project="${k8s_project:-$(prop 'project' 'project')}"
k8s_domain="${k8s_domain:-$(prop 'project' 'domain')}"
[[ -z "$k8s_project" ]] && k8s_project="rag"
[[ -z "$k8s_domain" ]] && k8s_domain="drillquiz.com"

NS=rag
NS_DIFY=dify

echo "[1/9] Dify Ingress 삭제"
kubectl delete ingress -n "${NS_DIFY}" --all --ignore-not-found=true 2>/dev/null || true

echo "[2/9] Dify (Helm) 삭제"
helm uninstall dify -n "${NS_DIFY}" 2>/dev/null || true

echo "[3/9] Dify namespace 삭제"
kubectl delete namespace "${NS_DIFY}" --ignore-not-found=true --timeout=120s 2>/dev/null || true

echo "[4/9] RAG Ingress 삭제"
if [[ -f rag-ingress.yaml ]]; then
  sed -e "s/k8s_project/${k8s_project}/g" -e "s/k8s_domain/${k8s_domain}/g" rag-ingress.yaml > rag-ingress.yaml_bak
  kubectl delete -f rag-ingress.yaml_bak -n "${NS}" --ignore-not-found=true 2>/dev/null || true
fi

echo "[5/9] RAG CronJob / Job 삭제"
kubectl delete cronjob rag-ingestion-cronjob-cointutor rag-ingestion-cronjob-drillquiz -n "${NS}" --ignore-not-found=true 2>/dev/null || true
kubectl delete cronjob rag-ingestion -n "${NS}" --ignore-not-found=true 2>/dev/null || true
kubectl delete job rag-ingestion-job-cointutor rag-ingestion-job-drillquiz rag-ingestion-run qdrant-collection-init -n "${NS}" --ignore-not-found=true 2>/dev/null || true

echo "[6/9] RAG Backend / Frontend 삭제"
kubectl delete -f cointutor/rag-backend.yaml -n "${NS}" --ignore-not-found=true 2>/dev/null || true
kubectl delete -f drillquiz/rag-backend-drillquiz.yaml -n "${NS}" --ignore-not-found=true 2>/dev/null || true
kubectl delete -f rag-frontend.yaml -n "${NS}" --ignore-not-found=true 2>/dev/null || true

echo "[7/9] Qdrant (Helm) 삭제"
helm uninstall qdrant -n "${NS}" 2>/dev/null || true

echo "[8/9] RAG Namespace ${NS} 삭제"
kubectl delete namespace "${NS}" --ignore-not-found=true --timeout=120s 2>/dev/null || true

echo "[9/9] 정리 대기"
sleep 5
kubectl get namespace "${NS_DIFY}" 2>/dev/null && echo "  → namespace ${NS_DIFY} 아직 존재" || echo "  → namespace ${NS_DIFY} 삭제됨"
kubectl get namespace "${NS}" 2>/dev/null && echo "  → namespace ${NS} 아직 존재 (PVC 등 확인 후 수동 삭제)" || echo "  → namespace ${NS} 삭제됨"

echo ""
echo "=== RAG + Dify 스택 삭제 완료 ==="
echo "  재설치: ./install.sh"
