# RAG 주제별 분리 (CoinTutor / DrillQuiz)

MinIO `rag-docs` 안의 문서를 주제별로 나누고, **컬렉션 이름 통일(선택 B)** + **Job/CronJob 분리** + **백엔드 2개 배포(방법 A)** 로 완전 분리하는 방법입니다.

---

## 1. 분리 전략 요약

| 구분 | CoinTutor | DrillQuiz |
|------|-----------|-----------|
| **MinIO 경로** | `rag-docs/raw/cointutor/` | `rag-docs/raw/drillquiz/` |
| **Qdrant 컬렉션** | `rag_docs_cointutor` | `rag_docs_drillquiz` |
| **인덱싱 Job** | `rag-ingestion-job-cointutor` | `rag-ingestion-job-drillquiz` |
| **인덱싱 CronJob** | `rag-ingestion-cronjob-cointutor` | `rag-ingestion-cronjob-drillquiz` |
| **RAG Backend** | `rag-backend` (COLLECTION=rag_docs_cointutor) | `rag-backend-drillquiz` (COLLECTION=rag_docs_drillquiz) |
| **Dify 도구 URL** | `http://rag-backend.rag.svc.cluster.local:8000/query` | `http://rag-backend-drillquiz.rag.svc.cluster.local:8000/query` |

- **컬렉션**: 기존 `rag_docs` 는 사용하지 않고, `rag_docs_cointutor` / `rag_docs_drillquiz` 만 사용(선택 B).
- **Job/CronJob**: 주제별로 별도 YAML로 분리.
- **백엔드**: 방법 A — 백엔드 2개 배포로 완전 분리.

---

## 2. MinIO 폴더 구조

```
rag-docs/
  raw/
    cointutor/
      USE_CASES.md
      USER_GUIDE.md
    drillquiz/
      FAQ.md
      GUIDE.md
```

- **CoinTutor 소스 문서**: `tz-local/resource/rag/cointutor/` 에 `USE_CASES.md`, `USER_GUIDE.md`, `CoinTutor.yml`(Dify 앱 템플릿) 위치. `.md` 파일은 MinIO `rag-docs/raw/cointutor/` 에 업로드 후 인덱싱.
- DrillQuiz 문서: `raw/drillquiz/` 에만 업로드.

---

## 3. Qdrant 컬렉션 (선택 B: 이름 통일)

주제마다 컬렉션 1개씩, 벡터 1536·Cosine.

- **rag_docs_cointutor**: CoinTutor 전용.
- **rag_docs_drillquiz**: DrillQuiz 전용.
- 기존 `rag_docs` 는 사용하지 않음. 필요 시 데이터를 `rag_docs_cointutor` 로 재인덱싱 후 `rag_docs` 삭제.

`qdrant-collection-init.yaml`(또는 install.sh)에서 위 두 컬렉션을 생성하도록 되어 있음.

---

## 4. 인덱싱 Job / CronJob 분리

같은 `ingest.py`·ConfigMap을 쓰고, **환경 변수만** 주제별로 다르게 합니다.

### 4.1 CoinTutor

| 리소스 | MINIO_PREFIX | QDRANT_COLLECTION |
|--------|--------------|-------------------|
| Job | `raw/cointutor/` | `rag_docs_cointutor` |
| CronJob | `raw/cointutor/` | `rag_docs_cointutor` |

- **Job**: `kubectl apply -f rag-ingestion-job-cointutor.yaml`
- **1회 수동 실행**: `kubectl create job -n rag ingest-cointutor-1 --from=cronjob/rag-ingestion-cronjob-cointutor`

### 4.2 DrillQuiz

| 리소스 | MINIO_PREFIX | QDRANT_COLLECTION |
|--------|--------------|-------------------|
| Job | `raw/drillquiz/` | `rag_docs_drillquiz` |
| CronJob | `raw/drillquiz/` | `rag_docs_drillquiz` |

- **Job**: `kubectl apply -f rag-ingestion-job-drillquiz.yaml`
- **1회 수동 실행**: `kubectl create job -n rag ingest-drillquiz-1 --from=cronjob/rag-ingestion-cronjob-drillquiz`

---

## 5. 방법 A: 백엔드 2개 배포 (완전 분리)

주제별로 **별도 Deployment + Service** 를 두어, URL 단위로 완전히 분리합니다.

### 5.1 CoinTutor 백엔드

| 항목 | 내용 |
|------|------|
| **Deployment** | `rag-backend` (기존) |
| **Service** | `rag-backend` (port 8000) |
| **환경 변수** | `QDRANT_COLLECTION=rag_docs_cointutor` |
| **URL (클러스터 내)** | `http://rag-backend.rag.svc.cluster.local:8000` |

- Dify CoinTutor RAG 도구: 위 URL + `POST /query` (body: `question`, `top_k` 만 사용해도 됨).

### 5.2 DrillQuiz 백엔드

| 항목 | 내용 |
|------|------|
| **Deployment** | `rag-backend-drillquiz` |
| **Service** | `rag-backend-drillquiz` (port 8000) |
| **환경 변수** | `QDRANT_COLLECTION=rag_docs_drillquiz` |
| **URL (클러스터 내)** | `http://rag-backend-drillquiz.rag.svc.cluster.local:8000` |

- Dify DrillQuiz RAG 도구: 위 URL + `POST /query` (body: `question`, `top_k`).

### 5.3 공통 사항

- 두 백엔드 모두 **같은 ConfigMap** `rag-backend-script` 사용. 스크립트는 `COLLECTION` 환경 변수를 읽어 고정 컬렉션만 검색.
- Secret `rag-ingestion-secret`(Gemini 등) 동일 사용.

### 5.4 Dify 연결

- **CoinTutor 챗봇** → 커스텀 도구 **CoinTutor RAG** → `http://rag-backend.rag.svc.cluster.local:8000/query`
- **DrillQuiz 챗봇** → 커스텀 도구 **DrillQuiz RAG** → `http://rag-backend-drillquiz.rag.svc.cluster.local:8000/query`

서로 다른 백엔드 URL이므로 트래픽·배포가 완전히 분리됩니다.

---

## 6. 방법 B (참고): 백엔드 1개 + 요청 파라미터

백엔드 한 개만 두고 `/query` 요청에 `collection` 파라미터로 컬렉션을 지정하는 방식입니다.  
운영을 더 단순하게 가져가고 싶을 때만 고려합니다.

- `POST /query` body: `{ "question": "...", "top_k": 5, "collection": "rag_docs_drillquiz" }`
- Dify에서 도구별로 `collection` 값을 다르게 넣어 호출.

현재 리포지터리에서는 **방법 A(백엔드 2개)** 를 기준으로 Job·CronJob·문서를 정리해 두었습니다.

---

## 7. Dify DrillQuiz 챗봇

1. **커스텀 도구**: OpenAPI 스키마에서 **server URL** 만 `http://rag-backend-drillquiz.rag.svc.cluster.local:8000` 로 두고, 나머지는 CoinTutor RAG와 동일한 구조로 **DrillQuiz RAG** 등록.
2. **앱**: 새 채팅 플로우(예: DrillQuiz) 생성.
3. **워크플로**: Start → (선택) 질문 분류 → **도구(DrillQuiz RAG)** → LLM → Answer. `question` = `sys.query`.

---

## 8. RAG 컬렉션 초기화

벡터 데이터를 비우고 다시 인덱싱하려면 `tz-local/resource/rag/reset-rag-collections.sh` 를 사용합니다.

```bash
cd tz-local/resource/rag
./reset-rag-collections.sh [cointutor|drillquiz|all] [reindex]
```

| 인자 | 설명 |
|------|------|
| `all` (기본) | rag_docs_cointutor, rag_docs_drillquiz 둘 다 삭제 후 재생성 |
| `cointutor` | rag_docs_cointutor 만 초기화 |
| `drillquiz` | rag_docs_drillquiz 만 초기화 |
| `reindex` (두 번째 인자) | 초기화 후 해당 주제 인덱싱 Job 1회 실행 |

예: `./reset-rag-collections.sh cointutor reindex` — CoinTutor 컬렉션 초기화 후 인덱싱 Job 실행.

**MinIO에서 파일을 지워도 RAG에 결과가 남는 이유**: 인덱서(ingest.py)는 기존에 **upsert만** 하고 Qdrant에서 삭제하지 않았음. 그래서 MinIO에서 파일을 지우고 Job을 다시 돌려도 **기존 벡터가 그대로 남음**. 현재 ingest.py는 **실행 시 해당 컬렉션을 삭제 후 재생성**한 뒤, MinIO에 있는 파일만 upsert하도록 수정되어 있음. MinIO에서 파일을 지운 뒤 Job을 다시 실행하면 컬렉션이 비워진 뒤 현재 MinIO 객체만 반영됨.

---

## 9. 체크리스트

- [ ] MinIO `rag-docs/raw/cointutor/`, `raw/drillquiz/` 에 문서 업로드
- [ ] Qdrant 컬렉션 `rag_docs_cointutor`, `rag_docs_drillquiz` 생성 (install 또는 수동)
- [ ] CoinTutor Job/CronJob 적용 후 1회 인덱싱 실행
- [ ] DrillQuiz Job/CronJob 적용 후 1회 인덱싱 실행
- [ ] RAG Backend(rag-backend), RAG Backend DrillQuiz(rag-backend-drillquiz) 배포
- [ ] Dify: CoinTutor RAG 도구(rag-backend URL), DrillQuiz RAG 도구(rag-backend-drillquiz URL) 등록 후 각 챗봇에 연결
- [ ] 초기화 필요 시: `tz-local/resource/rag/reset-rag-collections.sh` 사용
