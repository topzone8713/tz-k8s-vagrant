# RAG + 챗봇 요구사항 정리 및 수행 계획

## 1. 요구사항 정리

### 1.1 환경 요약

| 항목 | 내용 |
|------|------|
| **Hyper-V 호스트** | DESKTOP-KMDVQ1L |
| **VM** | Ubuntu 22.04 3대 (ubuntu-22.04_0, _1, _2) |
| **VM RAM** | _0: ~4.1GB, _1: ~5.6GB, _2: ~6.7GB |
| **K8s 접근** | `KUBECONFIG=/Users/dhong/.kube/topzone.iptime.org.config` |
| **SSH (topzone.iptime.org)** | 12020, 12021(doohee323), 12023(eks-main-t) |

### 1.2 이미 완료된 인프라

- K8S 클러스터
- Ingress + TLS
- MinIO (namespace: `devops`, Helm minio/minio 5.4.0, Ingress로 콘솔 노출)

### 1.3 추가로 구축할 것

- **RAG 스택**: Qdrant, RAG backend, RAG frontend, Ingestion/Job
- **챗봇**: Dify (가장 쉬운 설치 + RAG 지원 + Web UI, MinIO/Qdrant 연동)
- **RAG 운영 6단계**: MinIO 버킷 규칙 → Qdrant 컬렉션 → 인덱싱 → 메타데이터 규칙 → 검색 테스트 → CronJob 자동 인덱싱

### 1.4 리소스 가이드 (Pod 기준)

| 컴포넌트 | 대략 RAM |
|----------|----------|
| RAG backend | 1~2GB |
| RAG frontend | 0.5GB |
| Qdrant | 2~4GB |
| Ingestion/Job (실행 시) | 1~2GB |
| 여유 | 2GB |

**시나리오 A (추천)**: VM 하나(예: ubuntu-22.04_2, ~6.7GB)에서 RAG 실행  
- MinIO 접근 + Qdrant + RAG backend/frontend + Dify  
- 장점: 단순, 네트워크 구조 유지, 현재 상태 그대로 가능  

**“특정 VM 이용”의 의미**: 네, **K8s 안에서 그 VM(노드)로 스케줄링 힌트를 주는 것**입니다.  
- RAG 관련 Pod(Qdrant, RAG backend/frontend, Ingestion Job 등)가 해당 노드에서만 뜨도록 하려면 **nodeSelector**, **nodeAffinity**, 또는 **nodeName**을 사용합니다.  
- 예: 노드에 `node.kubernetes.io/hostname=ubuntu-22-04-2` 같은 라벨이 있다면 Deployment/Job에 `nodeSelector` 또는 `affinity`로 지정.  
- 힌트를 주지 않으면 스케줄러가 아무 노드에나 배치하므로, “이 VM에서만 돌리겠다”는 요구는 반드시 스케줄링 설정으로 명시해야 합니다.

### 1.5 이 구성이 일반적인지 (검증 요약)

**결론: 네, 일반적인(표준에 가까운) RAG 구성입니다.**

| 구성 요소 | 일반성 | 참고 |
|-----------|--------|------|
| **문서 저장소 (MinIO/S3)** | ✅ 일반적 | 프로덕션 RAG는 “객체 저장소 + 벡터 DB” 조합이 표준. MinIO는 S3 호환이라 LangChain/공식 문서에서 자주 언급. |
| **버킷 구조 (raw/processed/chunks)** | ✅ 일반적 | 원본(raw)과 전처리·청크(processed/chunks) 분리는 데이터 레이크·RAG 파이프라인에서 흔한 패턴. |
| **벡터 DB (Qdrant)** | ✅ 일반적 | RAG용 벡터 DB로 Qdrant, Weaviate, Pinecone, pgvector 등이 널리 쓰임. Qdrant는 오픈소스·자체 호스팅·성능으로 프로덕션에 자주 선택됨. Dify Enterprise에서도 벡터 DB로 Qdrant 권장. |
| **인덱싱 (배치/CronJob)** | ✅ 일반적 | “문서 → 청크 → 임베딩 → 벡터 DB” 파이프라인은 배치(주기 실행) 또는 이벤트(업로드 시 웹훅) 둘 다 사용. 초기/소규모는 CronJob 배치가 단순하고 흔함. |
| **메타데이터 (doc_id, source, path, page)** | ✅ 일반적 | 청크별 payload에 출처·페이지·경로를 넣어 인용·필터링하는 방식은 RAG 품질 가이드에서 공통으로 권장됨. |
| **Dify + RAG** | ✅ 일반적 | Dify는 RAG·챗봇·Web UI를 포함한 오픈소스 플랫폼으로, MinIO/벡터 DB(Qdrant 등)와 연동하는 구성이 문서·사례에서 자주 나옴. |
| **K8s 배포** | ✅ 일반적 | RAG 서비스를 Kubernetes에 배포하는 패턴은 클라우드·온프레미스 모두에서 사용되며, 확장·운영에 적합함. |

**차이점/선택지**  
- **인덱싱 트리거**: 지금 계획은 “CronJob 주기 실행”. 더 실시간이 필요하면 MinIO 버킷 알림 → 웹훅 → 인덱서 호출 방식도 일반적.  
- **벡터 DB**: 데이터가 500만 벡터 미만이면 pgvector도 많이 쓰이지만, Qdrant 선택은 전형적인 선택.  
- **고급 검색**: 프로덕션에서는 BM25+임베딩 하이브리드, 리랭킹을 쓰는 경우가 늘어나지만, 현재 단계의 “임베딩 + Qdrant”만으로도 일반적인 1단계 구성이다.

---

## 2. 수행 계획 (Phase별)

### Phase 0: 사전 확인

| # | 작업 | 명령/확인 |
|---|------|------------|
| 0-1 | K8s 접근 확인 | `KUBECONFIG=/Users/dhong/.kube/topzone.iptime.org.config kubectl get nodes` |
| 0-2 | MinIO/Ingress 네임스페이스·서비스 확인 | `kubectl -n devops get svc,pods` |
| 0-3 | RAG 전용 네임스페이스 결정 | 예: `rag` (신규 생성) |

---

### Phase 1: RAG용 MinIO 버킷/경로 규칙

| # | 작업 | 내용 |
|---|------|------|
| 1-1 | 버킷 생성(없으면) | 버킷명: `rag-docs` |
| 1-2 | prefix 규칙 정하기 | `raw/`(원본), `processed/`(전처리), `chunks/`(청크/메타), `indexes/`(선택) |
| 1-3 | MinIO 콘솔 또는 mc/API로 적용 | 기존 버킷 있으면 규칙만 정리 |

**산출물**: MinIO `rag-docs` 버킷 + prefix 규칙 문서화

---

### Phase 2: Qdrant 배포 및 컬렉션 생성

| # | 작업 | 내용 |
|---|------|------|
| 2-1 | Qdrant 배포 | `rag` 네임스페이스에 Deployment/Service (또는 Helm), 리소스 2~4GB |
| 2-2 | Ingress/Service 노출 | 내부 6333, 필요 시 Ingress로 6333 노출 |
| 2-3 | Embedding 차원 결정 | OpenAI text-embedding-3-small → 1536 (기본 권장) |
| 2-4 | 컬렉션 생성 | `rag_docs`, vectors size=1536, distance=Cosine |
| 2-5 | 확인 | `GET /collections`, `GET /collections/rag_docs` |

**명령 예시 (port-forward 후)**  
```bash
kubectl -n rag port-forward svc/qdrant 6333:6333
# 다른 터미널
curl -X PUT "http://localhost:6333/collections/rag_docs" \
  -H "Content-Type: application/json" \
  -d '{"vectors": { "size": 1536, "distance": "Cosine" }}'
curl "http://localhost:6333/collections"
```

---

### Phase 3: RAG Backend / Frontend 배포

| # | 작업 | 내용 |
|---|------|------|
| 3-1 | RAG 백엔드 배포 | MinIO/Qdrant URL·인증 설정, `/query` 또는 `/chat` 등 API 제공 |
| 3-2 | RAG 프론트엔드 배포 | 백엔드 URL 연동, 질문→답변 UI |
| 3-3 | Ingress + TLS | rag.example.com 등 호스트로 백엔드/프론트 노출 |
| 3-4 | API 문서 확인 | `/docs` 또는 `/swagger`로 엔드포인트·파라미터 확인 |

**산출물**: RAG API 동작, 프론트에서 질의 가능

---

### Phase 4: 인덱서(Ingestion) 구성 및 1회 실행

| # | 작업 | 내용 |
|---|------|------|
| 4-1 | 인덱서 컴포넌트 확인 | `kubectl -n rag get pods` 에서 extractor/ingest/worker 등 확인 |
| 4-2 | 인덱서 로그/문서 확인 | 실행 방법, MinIO 경로, Qdrant 컬렉션명 확인 |
| 4-3 | MinIO `raw/`에 테스트 문서 업로드 | PDF 등 1~2개 |
| 4-4 | 인덱싱 Job 1회 실행 | 문서 → 청크 → 임베딩 → Qdrant `rag_docs` 저장 |
| 4-5 | Qdrant points_count 확인 | `points_count` > 0 이면 성공 |

**산출물**: Qdrant에 벡터 데이터 적재 완료

---

### Phase 5: 메타데이터 규칙 및 검색 품질

| # | 작업 | 내용 |
|---|------|------|
| 5-1 | 청크 payload 규칙 정하기 | doc_id, source, path, page, section, created_at, updated_at, (선택) acl |
| 5-2 | 인덱서가 해당 payload 넣도록 설정 | 코드/설정 반영 후 재인덱싱 필요 시 실행 |
| 5-3 | 검색→생성 테스트 | RAG API로 질의, 출처/페이지 인용 확인 |
| 5-4 | 품질 조정 | 청크 크기, overlap, top_k 등 튜닝 |

**산출물**: 메타데이터 규칙 문서, 출처 인용 가능한 검색 결과

---

### Phase 6: 자동 인덱싱 (CronJob)

| # | 작업 | 내용 |
|---|------|------|
| 6-1 | CronJob 리소스 작성 | 스케줄 예: 매일 02:00, 동일 인덱서 이미지/스크립트 사용 |
| 6-2 | MinIO `raw/` 스캔 → 신규만 인덱싱 | 로직이 있으면 적용, 없으면 전체 재인덱싱으로 시작 |
| 6-3 | 배포 및 모니터링 | `kubectl -n rag get cronjobs`, 로그로 1회 수동 실행 검증 |

**산출물**: 주기적 자동 인덱싱 동작

---

### Phase 7: Dify 챗봇 구성

| # | 작업 | 내용 |
|---|------|------|
| 7-1 | Dify 설치 방식 결정 | **K8s Helm 배포** (`tz-local/resource/dify/install.sh`) |
| 7-2 | Helm chart 사용 | Community chart [BorisPolonsky/dify-helm](https://github.com/BorisPolonsky/dify-helm). 저장소 클론은 repo 추가 실패 시 대안으로 문서화 |
| 7-3 | 설정 | `values.yaml`: 벡터 DB=Qdrant(`qdrant.rag.svc.cluster.local:6333`), 파일=MinIO(S3, devops NS) 선택, Ingress(Jenkins 스타일 호스트) |
| 7-4 | Web UI에서 RAG·챗봇 연결 | 데이터소스(MinIO/로컬), 벡터 DB, 질문→답변 플로우 — `tz-local/resource/dify/README.md` 참고 |

**산출물**: Dify Web UI로 RAG 지원 챗봇 동작  
**구성 위치**: `tz-local/resource/dify/` (install.sh, values.yaml, dify-ingress.yaml, README.md)

---

## 3. 수행 순서 요약

```
Phase 0: 사전 확인 (K8s, MinIO, 네임스페이스)
    ↓
Phase 1: MinIO rag-docs 버킷 + prefix 규칙
    ↓
Phase 2: Qdrant 배포 + 컬렉션(rag_docs, dim=1536)
    ↓
Phase 3: RAG Backend/Frontend 배포 + Ingress
    ↓
Phase 4: 인덱서 구성 및 1회 인덱싱 → Qdrant 데이터 적재
    ↓
Phase 5: 메타데이터 규칙 정리 + 검색/인용 테스트
    ↓
Phase 6: CronJob 자동 인덱싱
    ↓
Phase 7: Dify 챗봇 설치 및 RAG 연동
```

---

## 4. K8s 접근 명령 (로컬 Mac)

```bash
export KUBECONFIG=/Users/dhong/.kube/topzone.iptime.org.config
kubectl get nodes
kubectl -n devops get svc,pods
# RAG 네임스페이스 사용 시
kubectl create namespace rag
kubectl -n rag get all
```

**참고**: `topzone.iptime.org.config`의 server가 `https://kubernetes.default.svc.cluster.local:26443`이면, 실제 사용 시 SSH 터널(예: `-L 26443:...`)로 API 서버에 연결해야 할 수 있음. VM 내부에서 실행하는 경우 해당 설정 그대로 사용 가능.

---

## 5. 체크리스트 (완료 시 ✓)

- [ ] Phase 0: K8s·MinIO·네임스페이스 확인
- [ ] Phase 1: `rag-docs` 버킷 + raw/processed/chunks 규칙
- [ ] Phase 2: Qdrant 배포, `rag_docs` 컬렉션(1536), 확인
- [ ] Phase 3: RAG backend/frontend 배포, Ingress, API 문서 확인
- [ ] Phase 4: 인덱서 1회 실행, Qdrant points_count > 0
- [ ] Phase 5: 메타데이터 규칙, 검색·인용 테스트
- [ ] Phase 6: CronJob 자동 인덱싱
- [ ] Phase 7: Dify 설치 및 RAG 챗봇 연동 (`tz-local/resource/dify/install.sh` + README)

---

## 6. 중지 시점 / 현재 상태

**리소스 준비 상태**: Phase 2~7용 매니페스트·스크립트는 이미 작성되어 있음.

| 위치 | 내용 |
|------|------|
| `tz-local/resource/rag/` | namespace, Qdrant(Helm), 컬렉션 init Job, RAG backend/frontend, Ingress, 인덱서 Job/CronJob, `scripts/ingest.py` |
| `tz-local/resource/dify/` | install.sh(Helm), values.yaml, dify-ingress.yaml, minio-bucket-job, status.sh, README |

**실행(배포)은 아직 미완료** — 체크리스트는 모두 미체크 상태. K8s 클러스터에 실제로 적용한 Phase가 어디까지인지에 따라 아래 순서로 재개하면 됨.

**재개 순서**

1. **Phase 0**  
   `KUBECONFIG=... kubectl get nodes` / `kubectl -n devops get svc,pods` 로 K8s·MinIO 확인 후, `kubectl create namespace rag` (없으면).

2. **Phase 1**  
   MinIO 콘솔에서 버킷 `rag-docs` 생성, prefix 규칙(raw/processed/chunks) 정리.

3. **Phase 2~3**  
   RAG 스택 한 번에 배포:  
   `cd tz-local/resource/rag && bash install.sh`  
   → Qdrant, 컬렉션 `rag_docs`, RAG backend/frontend, Ingress 적용.

4. **Phase 4**  
   `rag-ingestion-secret` 생성(MinIO + OpenAI 또는 Gemini 키) 후,  
   MinIO `rag-docs` 버킷 `raw/`에 테스트 문서 업로드 →  
   `kubectl -n rag create job --from=cronjob/rag-ingestion-cronjob ingest-manual-1` 등으로 1회 인덱싱 →  
   Qdrant points_count 확인.

5. **Phase 5~6**  
   메타데이터·검색 테스트 후, CronJob 스케줄 확인(`kubectl -n rag get cronjobs`).

6. **Phase 7**  
   (선택) NFS StorageClass `nfs-client` 확인 후  
   `cd tz-local/resource/dify && bash install.sh`  
   → Dify Web UI 접속 후 RAG·챗봇 연동 (`tz-local/resource/dify/README.md` 참고).

각 Phase 완료 시 위 체크리스트 해당 항목에 `[x]`로 표시하면 진행 상황을 추적하기 쉬움.
