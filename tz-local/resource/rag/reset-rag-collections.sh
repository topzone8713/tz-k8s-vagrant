#!/usr/bin/env bash
# RAG Qdrant 컬렉션 초기화: 컬렉션 삭제 후 재생성 (벡터 데이터 비우기)
# 사용: ./reset-rag-collections.sh [cointutor|drillquiz|all] [reindex]
#   - 인자 없음 또는 all: rag_docs(레거시) + rag_docs_cointutor, rag_docs_drillquiz 초기화
#   - cointutor / drillquiz: 해당 컬렉션만 초기화
#   - reindex: 초기화 후 해당 주제 인덱싱 Job 1회 실행 (선택)
#
# 예: ./reset-rag-collections.sh all
#     ./reset-rag-collections.sh cointutor reindex

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
NS="${NS:-rag}"
TOPIC="${1:-all}"
REINDEX="${2:-}"

POD_NAME="rag-qdrant-reset-$$"

# Qdrant에 접근 가능한 Pod에서 curl 실행 (클러스터 내부)
run_reset() {
  local topic="$1"
  local cmd
  case "$topic" in
    cointutor)
      cmd='curl -s -X DELETE http://qdrant:6333/collections/rag_docs_cointutor || true; curl -s -X PUT http://qdrant:6333/collections/rag_docs_cointutor -H "Content-Type: application/json" -d "{\"vectors\":{\"size\":1536,\"distance\":\"Cosine\"}}"; echo cointutor ok'
      ;;
    drillquiz)
      cmd='curl -s -X DELETE http://qdrant:6333/collections/rag_docs_drillquiz || true; curl -s -X PUT http://qdrant:6333/collections/rag_docs_drillquiz -H "Content-Type: application/json" -d "{\"vectors\":{\"size\":1536,\"distance\":\"Cosine\"}}"; echo drillquiz ok'
      ;;
    all|*)
      # 레거시 rag_docs 삭제(재생성 안 함). cointutor/drillquiz만 재생성
      cmd='curl -s -X DELETE http://qdrant:6333/collections/rag_docs || true; curl -s -X DELETE http://qdrant:6333/collections/rag_docs_cointutor || true; curl -s -X PUT http://qdrant:6333/collections/rag_docs_cointutor -H "Content-Type: application/json" -d "{\"vectors\":{\"size\":1536,\"distance\":\"Cosine\"}}"; curl -s -X DELETE http://qdrant:6333/collections/rag_docs_drillquiz || true; curl -s -X PUT http://qdrant:6333/collections/rag_docs_drillquiz -H "Content-Type: application/json" -d "{\"vectors\":{\"size\":1536,\"distance\":\"Cosine\"}}"; echo all ok'
      ;;
  esac

  kubectl --kubeconfig "${KUBECONFIG}" run "${POD_NAME}" -n "${NS}" \
    --restart=Never \
    --image=curlimages/curl \
    -- sh -c "$cmd"

  echo "Pod ${POD_NAME} 실행 중… (Qdrant 접속)"
  for i in $(seq 1 30); do
    phase=$(kubectl --kubeconfig "${KUBECONFIG}" get pod "${POD_NAME}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    [[ "$phase" == "Succeeded" ]] && break
    [[ "$phase" == "Failed" ]] && break
    sleep 2
  done
  kubectl --kubeconfig "${KUBECONFIG}" logs "pod/${POD_NAME}" -n "${NS}" 2>/dev/null || true
  kubectl --kubeconfig "${KUBECONFIG}" delete pod "${POD_NAME}" -n "${NS}" --ignore-not-found=true --wait=false 2>/dev/null || true
}

echo "[1/2] Qdrant 컬렉션 초기화 (topic=${TOPIC})"
run_reset "${TOPIC}"
echo "초기화 완료."
echo "  → RAG UI에서 이전 결과가 보이면 강력 새로고침(Ctrl+Shift+R) 하세요."

if [[ "${REINDEX}" == "reindex" ]]; then
  echo "[2/2] 인덱싱 Job 1회 실행"
  case "$TOPIC" in
    cointutor)
      kubectl --kubeconfig "${KUBECONFIG}" delete job rag-ingestion-job-cointutor -n "${NS}" --ignore-not-found=true
      kubectl --kubeconfig "${KUBECONFIG}" apply -f "${SCRIPT_DIR}/cointutor/rag-ingestion-job-cointutor.yaml" -n "${NS}"
      echo "  → rag-ingestion-job-cointutor 실행됨. 완료 확인: kubectl get jobs -n ${NS}"
      ;;
    drillquiz)
      kubectl --kubeconfig "${KUBECONFIG}" delete job rag-ingestion-job-drillquiz -n "${NS}" --ignore-not-found=true
      kubectl --kubeconfig "${KUBECONFIG}" apply -f "${SCRIPT_DIR}/drillquiz/rag-ingestion-job-drillquiz.yaml" -n "${NS}"
      echo "  → rag-ingestion-job-drillquiz 실행됨. 완료 확인: kubectl get jobs -n ${NS}"
      ;;
    all|*)
      kubectl --kubeconfig "${KUBECONFIG}" delete job rag-ingestion-job-cointutor -n "${NS}" --ignore-not-found=true
      kubectl --kubeconfig "${KUBECONFIG}" delete job rag-ingestion-job-drillquiz -n "${NS}" --ignore-not-found=true
      kubectl --kubeconfig "${KUBECONFIG}" apply -f "${SCRIPT_DIR}/cointutor/rag-ingestion-job-cointutor.yaml" -n "${NS}"
      kubectl --kubeconfig "${KUBECONFIG}" apply -f "${SCRIPT_DIR}/drillquiz/rag-ingestion-job-drillquiz.yaml" -n "${NS}"
      echo "  → CoinTutor / DrillQuiz 인덱싱 Job 실행됨. 완료 확인: kubectl get jobs -n ${NS}"
      ;;
  esac
else
  echo "[2/2] reindex 생략. 인덱싱 실행: ./reset-rag-collections.sh ${TOPIC} reindex"
fi
echo "끝."
