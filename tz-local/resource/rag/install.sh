#!/usr/bin/env bash
# RAG 스택 + Dify 설치: install.sh 한 번 실행으로 전체 구성 (삭제 후 재실행 가능)
# - Namespace rag, Qdrant(Helm), 컬렉션, RAG backend/frontend, Ingress, Ingestion CronJob
# - Dify (namespace dify, Helm, Ingress)

#set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# prop (harbor/minio 패턴): /root/.k8s/project 에서 project, domain 등 읽기
if [[ -f /root/.bashrc ]]; then
  source /root/.bashrc
fi
function prop {
  key="${2}="
  file="/root/.k8s/${1}"
  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi
  rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g')
  [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g')
  echo "$rslt" | tr -d '\n' | tr -d '\r'
}

shopt -s expand_aliases
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
alias k="kubectl --kubeconfig ${KUBECONFIG}"

k8s_project="${k8s_project:-$(prop 'project' 'project')}"
k8s_domain="${k8s_domain:-$(prop 'project' 'domain')}"
[[ -z "$k8s_project" ]] && k8s_project="rag"
[[ -z "$k8s_domain" ]] && k8s_domain="drillquiz.com"

NS=rag

echo "[1/8] Namespace ${NS}"
kubectl apply -f namespace.yaml

echo "[2/8] Qdrant (Helm)"
helm repo add qdrant https://qdrant.github.io/qdrant-helm 2>/dev/null || true
helm repo update
helm upgrade --install qdrant qdrant/qdrant -n "${NS}" -f qdrant-values.yaml --wait --timeout 120s 2>/dev/null || \
  helm upgrade --install qdrant qdrant/qdrant -n "${NS}" -f qdrant-values.yaml

echo "[3/8] Qdrant Pod 대기"
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=qdrant" -n "${NS}" --timeout=180s 2>/dev/null || \
  kubectl wait --for=condition=ready pod -l "app=qdrant" -n "${NS}" --timeout=180s 2>/dev/null || \
  sleep 30

echo "[4/8] Qdrant 컬렉션 생성 (rag_docs_cointutor, rag_docs_drillquiz)"
kubectl delete job qdrant-collection-init -n "${NS}" --ignore-not-found=true
kubectl apply -f qdrant-collection-init.yaml -n "${NS}"
kubectl wait --for=condition=complete job/qdrant-collection-init -n "${NS}" --timeout=120s 2>/dev/null || sleep 15

echo "[5/8] RAG Backend (CoinTutor + DrillQuiz) / Frontend"
kubectl apply -f cointutor/rag-backend.yaml -n "${NS}"
kubectl apply -f drillquiz/rag-backend-drillquiz.yaml -n "${NS}"
kubectl apply -f rag-frontend.yaml -n "${NS}"

echo "[6/8] Ingress (rag, rag-ui)"
sed -e "s/k8s_project/${k8s_project}/g" -e "s/k8s_domain/${k8s_domain}/g" rag-ingress.yaml > rag-ingress.yaml_bak
kubectl apply -f rag-ingress.yaml_bak -n "${NS}"

echo "[7/8] Ingestion (ConfigMap + CronJob 분리: cointutor, drillquiz)"
if [[ -f "${SCRIPT_DIR}/scripts/ingest.py" ]]; then
  kubectl create configmap rag-ingestion-script --from-file="${SCRIPT_DIR}/scripts/ingest.py" -n "${NS}" --dry-run=client -o yaml | kubectl apply -f -
fi
kubectl apply -f cointutor/rag-ingestion-cronjob-cointutor.yaml -n "${NS}"
kubectl apply -f drillquiz/rag-ingestion-cronjob-drillquiz.yaml -n "${NS}"

echo "[8/8] Dify 설치"
DIFY_DIR="${SCRIPT_DIR}/../dify"
if [[ -d "${DIFY_DIR}" ]] && [[ -f "${DIFY_DIR}/install.sh" ]]; then
  bash "${DIFY_DIR}/install.sh"
else
  echo "  → ${DIFY_DIR}/install.sh 없음, Dify 설치 생략"
fi

echo ""
echo "=== RAG + Dify 설치 완료 ==="
echo "  Namespace: ${NS}"
echo "  Backend:   rag.default.${k8s_project}.${k8s_domain}, rag.${k8s_domain}"
echo "  Frontend:  rag-ui.default.${k8s_project}.${k8s_domain}, rag-ui.${k8s_domain}"
echo "  Qdrant:    kubectl -n ${NS} port-forward svc/qdrant 6333:6333"
echo "  MinIO:     devops 네임스페이스 (rag-docs 버킷은 콘솔에서 생성)"
echo "  인덱서:    Secret rag-ingestion-secret 생성 후 Job/CronJob 사용 (docs/rag-multi-topic.md 참고)"
echo "  Dify:      https://dify.${k8s_domain} (8단계에서 설치한 경우)"
kubectl get pods,svc,ingress,cronjob -n "${NS}" 2>/dev/null || true
if ! kubectl get secret rag-ingestion-secret -n "${NS}" &>/dev/null; then
  echo ""
  echo "⚠️  Secret rag-ingestion-secret 이 없어 Backend Pod이 CreateContainerConfigError 상태입니다."
  echo "   아래처럼 생성 후 Pod이 자동으로 기동됩니다 (README.md 참고)."
  echo "   MINIO_USER=\$(kubectl get secret minio -n devops -o jsonpath='{.data.rootUser}' | base64 -d)"
  echo "   MINIO_PASS=\$(kubectl get secret minio -n devops -o jsonpath='{.data.rootPassword}' | base64 -d)"
  echo "   kubectl create secret generic rag-ingestion-secret -n ${NS} --from-literal=MINIO_ACCESS_KEY=\"\$MINIO_USER\" --from-literal=MINIO_SECRET_KEY=\"\$MINIO_PASS\" --from-literal=GEMINI_API_KEY='YOUR_GEMINI_KEY'"
fi
exit 0
