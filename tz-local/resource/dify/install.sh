#!/usr/bin/env bash
# Dify 챗봇 설치 (Phase 7): Helm + RAG 연동(Qdrant/rag, MinIO/devops), Ingress
# 사전: RAG(Qdrant·rag_docs), NFS StorageClass(nfs-client, RWX), 선택 devops/MinIO

#set -e
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

shopt -s expand_aliases
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
alias k="kubectl --kubeconfig ${KUBECONFIG}"

k8s_project="${k8s_project:-$(prop 'project' 'project')}"
k8s_domain="${k8s_domain:-$(prop 'project' 'domain')}"
[[ -z "$k8s_project" ]] && k8s_project="default"
[[ -z "$k8s_domain" ]] && k8s_domain="drillquiz.com"

NS=dify

# 재설치(스토리지 변경 등): ./install.sh reinstall → Helm 삭제 + PVC/Secret 정리 후 재설치
if [[ "${1:-}" == "reinstall" ]]; then
  echo "[0/5] Helm 삭제 및 PVC·Secret 정리 (재설치)"
  helm uninstall dify -n "${NS}" 2>/dev/null || true
  k delete pvc -n "${NS}" dify dify-plugin-daemon 2>/dev/null || true
  k delete secret -n "${NS}" dify-postgresql dify-redis 2>/dev/null || true
  sleep 3
fi

echo "[1/5] Namespace ${NS}"
k create namespace "${NS}" 2>/dev/null || true

echo "[2/5] Helm repo (Dify community chart)"
if ! helm repo list 2>/dev/null | grep -q dify; then
  # Community chart: https://github.com/BorisPolonsky/dify-helm
  helm repo add dify https://borispolonsky.github.io/dify-helm 2>/dev/null || {
    echo "Repo add failed. Try: git clone https://github.com/BorisPolonsky/dify-helm && helm install dify ./dify-helm/charts/dify -n ${NS} -f values.yaml_bak"
    exit 1
  }
fi
helm repo update

echo "[3/5] values.yaml 치환 (k8s_project, k8s_domain, 접속 URL)"
cp -f values.yaml values.yaml_bak
sed -i.bak "s/k8s_project/${k8s_project}/g" values.yaml_bak
sed -i.bak "s/k8s_domain/${k8s_domain}/g" values.yaml_bak
# 접속 기준 URL. 포트포워딩 시: DIFY_BASE_URL=http://localhost:8080 bash install.sh
DIFY_BASE_URL_REPLACE="${DIFY_BASE_URL:-https://dify.${k8s_domain}}"
sed -i.bak "s|DIFY_BASE_URL_REPLACE|${DIFY_BASE_URL_REPLACE}|g" values.yaml_bak

echo "[3b/5] MinIO Secret (dify-minio-secret) — 없으면 devops/minio 에서 복사"
if ! k get secret dify-minio-secret -n "${NS}" &>/dev/null; then
  if k get secret minio -n devops &>/dev/null; then
    MINIO_USER=$(k get secret minio -n devops -o jsonpath='{.data.rootUser}' | base64 -d 2>/dev/null)
    MINIO_PASS=$(k get secret minio -n devops -o jsonpath='{.data.rootPassword}' | base64 -d 2>/dev/null)
    if [[ -n "$MINIO_USER" && -n "$MINIO_PASS" ]]; then
      k create secret generic dify-minio-secret -n "${NS}" \
        --from-literal=S3_ACCESS_KEY="$MINIO_USER" \
        --from-literal=S3_SECRET_KEY="$MINIO_PASS"
      echo "  → dify-minio-secret 생성됨 (devops/minio 기준)"
    else
      echo "  → devops/minio Secret 값 읽기 실패. 수동 생성: kubectl create secret generic dify-minio-secret -n ${NS} --from-literal=S3_ACCESS_KEY=... --from-literal=S3_SECRET_KEY=..."
    fi
  else
    echo "  → devops/minio 없음. MinIO 사용 시 수동 생성: kubectl create secret generic dify-minio-secret -n ${NS} --from-literal=S3_ACCESS_KEY=... --from-literal=S3_SECRET_KEY=..."
  fi
fi

echo "[3c/5] MinIO 버킷 dify 생성 (dify-minio-secret 있을 때)"
if k get secret dify-minio-secret -n "${NS}" &>/dev/null && [[ -f minio-bucket-job.yaml ]]; then
  k delete job minio-create-bucket-dify -n "${NS}" --ignore-not-found=true 2>/dev/null
  k apply -f minio-bucket-job.yaml -n "${NS}" 2>/dev/null
  k wait --for=condition=complete job/minio-create-bucket-dify -n "${NS}" --timeout=60s 2>/dev/null || true
fi

echo "[4/5] Helm upgrade --install Dify"
helm upgrade --install dify dify/dify -n "${NS}" -f values.yaml_bak --wait --timeout 600s 2>/dev/null || \
  helm upgrade --install dify dify/dify -n "${NS}" -f values.yaml_bak

echo "[5/5] Ingress 별도 적용"
if [[ -f dify-ingress.yaml ]]; then
  sed -e "s/k8s_project/${k8s_project}/g" -e "s/k8s_domain/${k8s_domain}/g" dify-ingress.yaml > dify-ingress.yaml_bak
  k apply -f dify-ingress.yaml_bak -n "${NS}" 2>/dev/null || true
fi

echo ""
echo "=== Dify 설치 완료 (Phase 7) ==="
echo "  Console:  https://dify.default.${k8s_project}.${k8s_domain} 또는 https://dify.${k8s_domain}"
echo "  벡터 DB:  Qdrant (rag 네임스페이스, rag_docs 컬렉션)"
echo "  저장소:   MinIO S3 (devops, 버킷 dify) — Secret로 S3_ACCESS_KEY/S3_SECRET_KEY 주입 시 사용"
echo "  RAG 연동: Web UI에서 데이터소스·지식베이스 연결 후 챗봇 플로우 구성 (README 참고)"
echo "  모니터링: ./status.sh (1회) 또는 ./status.sh watch (실시간)"
echo ""
k get pods,svc,pvc,ingress -n "${NS}" 2>/dev/null || true
exit 0
