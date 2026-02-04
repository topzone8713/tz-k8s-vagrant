# RAG 스택 + Dify (install.sh 기반)

`install.sh` 한 번 실행으로 **RAG**(Qdrant, 백엔드, 프론트, 인덱서)와 **Dify**까지 전체 구성. 삭제 후 재실행해도 동일하게 설치됨.

## 설치

```bash
cd tz-local/resource/rag
bash install.sh
```

- VM 내부: `/vagrant/tz-local/resource/rag/install.sh`
- 로컬: `KUBECONFIG=~/.kube/topzone.iptime.org.config bash install.sh`

### 설치 후 필수: Secret 생성

RAG 백엔드(검색 시 Gemini 임베딩)와 인덱서 Job/CronJob이 사용하는 `rag-ingestion-secret`이 없으면 Backend Pod이 기동하지 않고, 검색 시 `API key not valid` 오류가 난다. **설치 직후** 아래를 실행한다.

```bash
MINIO_USER=$(kubectl get secret minio -n devops -o jsonpath='{.data.rootUser}' | base64 -d)
MINIO_PASS=$(kubectl get secret minio -n devops -o jsonpath='{.data.rootPassword}' | base64 -d)
kubectl create secret generic rag-ingestion-secret -n rag \
  --from-literal=MINIO_ACCESS_KEY="$MINIO_USER" \
  --from-literal=MINIO_SECRET_KEY="$MINIO_PASS" \
  --from-literal=GEMINI_API_KEY='여기에_유효한_Gemini_API_키' \
  --dry-run=client -o yaml | kubectl apply -f -
```

- `GEMINI_API_KEY`는 [Google AI Studio](https://aistudio.google.com/apikey)에서 발급. **반드시 실제 키로** `'여기에_유효한_Gemini_API_키'` 를 치환한다.
- 시크릿을 **이미 기동 중인 Pod 이후에** 수정했다면, Backend를 재시작해야 새 키가 적용된다:
  ```bash
  kubectl rollout restart deployment/rag-backend deployment/rag-backend-drillquiz -n rag
  ```

## 삭제 (전체 자원 제거)

```bash
cd tz-local/resource/rag
./uninstall.sh
```

- **Dify**: Ingress → Helm → namespace `dify` 삭제 (사용자·앱 데이터 포함 초기화).
- **RAG**: Ingress → CronJob/Job → Backend/Frontend → Qdrant(Helm) → namespace `rag` 삭제.
- 재설치: `./install.sh`

## 구성 요소

**주제별 폴더**: CoinTutor / DrillQuiz 분리 (docs/rag-multi-topic.md 참고)

| 경로 | 내용 |
|------|------|
| `cointutor/rag-backend.yaml` | CoinTutor 백엔드 (rag_docs_cointutor) |
| `cointutor/rag-ingestion-job-cointutor.yaml` | CoinTutor 인덱싱 Job (raw/cointutor/ → rag_docs_cointutor) |
| `cointutor/rag-ingestion-cronjob-cointutor.yaml` | CoinTutor CronJob (매일 02:00) |
| `drillquiz/rag-backend-drillquiz.yaml` | DrillQuiz 백엔드 (rag_docs_drillquiz) |
| `drillquiz/rag-ingestion-job-drillquiz.yaml` | DrillQuiz 인덱싱 Job (raw/drillquiz/ → rag_docs_drillquiz) |
| `drillquiz/rag-ingestion-cronjob-drillquiz.yaml` | DrillQuiz CronJob (매일 02:30) |
| `namespace.yaml` | namespace `rag` |
| `qdrant-values.yaml` | Qdrant Helm values (단일 노드, PVC) |
| `qdrant-collection-init.yaml` | Job: 컬렉션 rag_docs_cointutor, rag_docs_drillquiz 생성 |
| `rag-frontend.yaml` | Frontend (nginx + 정적 UI, 주제 콤보박스) |
| `rag-ingress.yaml` | Ingress (rag.*, rag-ui.*) — install.sh에서 k8s_project/k8s_domain 치환 |
| `rag-ingestion-cronjob.yaml` | (레거시) CronJob raw/ → rag_docs |
| `rag-ingestion-job.yaml` | (레거시) Job 1회 실행 |
| `rag-ingestion-secret.example.yaml` | Secret 예시 (MinIO + OpenAI/Gemini 키) |
| `reset-rag-collections.sh` | Qdrant 컬렉션 초기화 (cointutor \| drillquiz \| all) [reindex] |
| `scripts/ingest.py` | 인덱서 스크립트 (install.sh에서 ConfigMap으로 올림) |

## 인덱서: MinIO raw/ → 청킹 → 임베딩 → Qdrant rag_docs

**흐름**: MinIO 버킷 `rag-docs`의 `raw/` 아래 PDF·txt → 텍스트 추출 → 청킹(500자, 50자 overlap) → **임베딩(OpenAI 또는 Gemini)** → Qdrant 컬렉션 `rag_docs`에 upsert.

### 1. Secret 생성 (필수)

인덱서 Job/CronJob은 Secret `rag-ingestion-secret`을 사용합니다. **OpenAI** 또는 **Gemini** 중 하나만 있으면 됩니다.

**OpenAI 사용 시:**
```bash
MINIO_USER=$(kubectl get secret minio -n devops -o jsonpath='{.data.rootUser}' | base64 -d)
MINIO_PASS=$(kubectl get secret minio -n devops -o jsonpath='{.data.rootPassword}' | base64 -d)
kubectl create secret generic rag-ingestion-secret -n rag \
  --from-literal=MINIO_ACCESS_KEY="$MINIO_USER" \
  --from-literal=MINIO_SECRET_KEY="$MINIO_PASS" \
  --from-literal=OPENAI_API_KEY='sk-...'
```

**Gemini 사용 시:** Secret에 `GEMINI_API_KEY`(또는 `GOOGLE_API_KEY`)를 넣고, Job/CronJob의 env에서 `EMBEDDING_PROVIDER=gemini`, `EMBEDDING_MODEL=gemini-embedding-001`로 설정.
```bash
MINIO_USER=$(kubectl get secret minio -n devops -o jsonpath='{.data.rootUser}' | base64 -d)
MINIO_PASS=$(kubectl get secret minio -n devops -o jsonpath='{.data.rootPassword}' | base64 -d)
kubectl create secret generic rag-ingestion-secret -n rag \
  --from-literal=MINIO_ACCESS_KEY="$MINIO_USER" \
  --from-literal=MINIO_SECRET_KEY="$MINIO_PASS" \
  --from-literal=GEMINI_API_KEY='...'
```
Job/CronJob YAML에서 `EMBEDDING_PROVIDER`를 `gemini`로, `EMBEDDING_MODEL`을 `gemini-embedding-001`로 바꾸면 됩니다. Gemini는 1536 차원(기본)으로 Qdrant `rag_docs`와 호환됩니다.

#### MinIO 시크릿 복사 (devops → rag)

이미 `rag-ingestion-secret`이 있고 OpenAI/Gemini 키만 있을 때, MinIO 접근용 키는 **devops 네임스페이스의 MinIO 시크릿**에서 복사해 넣으면 된다.

```bash
MINIO_USER=$(kubectl get secret minio -n devops -o jsonpath='{.data.rootUser}' | base64 -d)
MINIO_PASS=$(kubectl get secret minio -n devops -o jsonpath='{.data.rootPassword}' | base64 -d)
kubectl patch secret rag-ingestion-secret -n rag -p '{"data":{"MINIO_ACCESS_KEY":"'$(echo -n "$MINIO_USER" | base64 | tr -d '\n')'","MINIO_SECRET_KEY":"'$(echo -n "$MINIO_PASS" | base64 | tr -d '\n')'"}}'
```

새로 시크릿을 만드는 경우에는 위 "OpenAI 사용 시" / "Gemini 사용 시" 블록처럼 `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`에 위와 동일한 값을 넣어서 생성하면 된다.

### 2. MinIO 버킷 및 raw/ 업로드

인덱서 실행 시 **버킷 `rag-docs`**가 없으면 **자동으로 생성**한다. 수동으로 만들 필요 없다.

- **콘솔에서 미리 만들고 싶을 때**: MinIO 웹 콘솔 → Buckets → Create Bucket → 이름 `rag-docs`.
- **문서 업로드**: 버킷 안에 `raw/cointutor/`(또는 `raw/drillquiz/`) prefix를 두고 그 아래에 **PDF, .txt, .md** 업로드. CoinTutor 소스 문서는 `tz-local/resource/rag/cointutor/`(USE_CASES.md, USER_GUIDE.md) 에 있으며, MinIO `rag-docs/raw/cointutor/` 에 올리면 CoinTutor 인덱싱 대상이 됨.

#### 인덱서 로그 해석

| 로그 메시지 | 의미 | 조치 |
|-------------|------|------|
| `No objects under rag-docs/raw/. Upload PDF/txt to raw/ then re-run.` | 버킷·raw/는 있으나 **파일이 없음** | MinIO 콘솔에서 `rag-docs` → `raw/` 폴더에 PDF 또는 .txt 업로드 후 Job/CronJob 다시 실행 |
| `Embedding: OpenAI text-embedding-3-small` / `Embedding: Gemini ...` | 사용 중인 임베딩 프로바이더·모델 | 확인용, 조치 불필요 |
| `Created bucket rag-docs.` | 버킷이 없어서 **자동 생성됨** | 다음 실행부터 raw/에 파일만 올리면 됨 |
| `WARNING: Running pip as the 'root' user'` / `[notice] pip ...` | 컨테이너 안에서 pip 설치 시 나오는 경고 | 무시해도 됨 |
| `  <파일경로>: N chunks` / `Upserted ... points` | 해당 파일 청킹·Qdrant 적재 완료 | 정상 동작 |
| `Done. rag_docs points_count=<N>` | 인덱싱 완료, Qdrant에 N개 포인트 | 정상 |

### 3. 인덱싱 1회 실행 (Job)

```bash
# CoinTutor
kubectl delete job rag-ingestion-job-cointutor -n rag --ignore-not-found
kubectl apply -f cointutor/rag-ingestion-job-cointutor.yaml -n rag
kubectl logs -n rag job/rag-ingestion-job-cointutor -f

# DrillQuiz
kubectl apply -f drillquiz/rag-ingestion-job-drillquiz.yaml -n rag
```

### 4. 주기 실행 (CronJob)

CronJob `rag-ingestion`은 매일 02:00에 같은 인덱서 스크립트를 실행합니다. Secret이 있으면 그대로 동작합니다.

### 5. Payload (Qdrant)

청크별 payload: `doc_id`, `source`, `path`, `chunk_index`, `text`, `created_at` — RAG 출처·필터에 사용.

### 6. ingest.py가 K8s 안에서 기동하는 방식

| 단계 | 내용 |
|------|------|
| 1. ConfigMap | `install.sh`가 `scripts/ingest.py`를 읽어 ConfigMap `rag-ingestion-script`로 생성. 키는 파일명 `ingest.py`. |
| 2. Pod 볼륨 | CronJob/Job의 `volumes[]`에 `configMap: name: rag-ingestion-script` 지정, 컨테이너에서 `volumeMounts: mountPath: /config` 로 마운트. |
| 3. 컨테이너 안 경로 | Pod 안에서는 스크립트가 **`/config/ingest.py`** 로 보임. |
| 4. 실행 | 컨테이너 `command`: `pip install ... && python /config/ingest.py`. 즉 Python 이미지로 기동한 뒤 마운트된 스크립트를 실행. |
| 5. 환경 | `envFrom: secretRef: rag-ingestion-secret` 으로 MinIO/OpenAI/Gemini 키 주입, 나머지(QDRANT_HOST, MINIO_ENDPOINT 등)는 CronJob/Job의 `env[]`로 주입. |

- **CronJob**: 매일 02:00에 스케줄러가 Job을 하나 생성 → Pod 기동 → 위 순서로 `ingest.py` 실행.
- **1회만 실행**: `kubectl apply -f cointutor/rag-ingestion-job-cointutor.yaml -n rag` (또는 drillquiz) 또는 `./reset-rag-collections.sh cointutor reindex`.

## 삭제 후 재설치

```bash
kubectl delete namespace rag
bash install.sh
```

## 설정

- `k8s_project`, `k8s_domain`: `/root/.k8s/project` 또는 환경변수. 없으면 `rag`, `local`.
- Qdrant 단일 노드: `qdrant-values.yaml`에서 `config.cluster.enabled: false`.
- 특정 노드에만 스케줄: `qdrant-values.yaml`에 `nodeSelector` 또는 `affinity` 추가.
