# Dify 챗봇 (Phase 7)

RAG 스택(Qdrant, MinIO)과 연동한 Dify 챗봇 설치. `install.sh` 한 번 실행으로 Helm 배포 + Ingress 적용.

## 설치 (7-1, 7-2)

**사전 요구사항**
- RAG 네임스페이스에 Qdrant 배포 및 `rag_docs` 컬렉션 생성 완료
- **NFS StorageClass** (`nfs-client`, ReadWriteMany): api/worker가 같은 PVC를 써야 하므로 RWX 필요.  
  미설치 시 `tz-local/resource/dynamic-provisioning/nfs/install.sh` 로 NFS provisioner 설치 후 `k get storageclass` 에 `nfs-client` 확인.
- (선택) devops 네임스페이스에 MinIO 배포 — Dify 파일 저장소용

```bash
cd tz-local/resource/dify
bash install.sh
```

- VM 내부: `/vagrant/tz-local/resource/dify/install.sh`
- 로컬: `KUBECONFIG=~/.kube/your.config bash install.sh`

**설치 방식**: K8s Helm 배포 (Community chart [BorisPolonsky/dify-helm](https://github.com/BorisPolonsky/dify-helm)).  
Helm repo 추가 실패 시: `git clone https://github.com/BorisPolonsky/dify-helm` 후 `helm install dify ./dify-helm/charts/dify -n dify -f values.yaml_bak`

## 설정 (7-3)

| 항목 | 설정 |
|------|------|
| **PVC/스토리지** | NFS `storageClass: nfs-client`, `accessModes: ReadWriteMany` (api/worker/pluginDaemon 공유) |
| **벡터 DB** | Qdrant `http://qdrant.rag.svc.cluster.local:6333` (rag 네임스페이스, 컬렉션 `rag_docs`) |
| **파일 저장소** | MinIO S3 (devops, 버킷 `dify`). Secret `dify-minio-secret`에 `S3_ACCESS_KEY`, `S3_SECRET_KEY` 필요. install.sh가 devops/minio가 있으면 자동 생성. 없으면: `kubectl create secret generic dify-minio-secret -n dify --from-literal=S3_ACCESS_KEY=... --from-literal=S3_SECRET_KEY=...` |
| **Ingress** | `dify.default.<project>.<domain>`, `dify.<domain>` (Jenkins 스타일) |

MinIO 버킷 `dify`는 MinIO 콘솔에서 미리 생성.

values.yaml에서 `k8s_project`, `k8s_domain`은 install.sh가 `/root/.k8s/project` 등에서 읽어 치환한다.

## 설치 후 Web UI에서 필수: 모델 제공자·스토리지

Dify Helm 설치만으로는 앱에서 **LLM**과 **파일 저장소**를 쓸 수 없다. Web UI에 접속한 뒤 아래를 **반드시 설치·설정**한다.

### 1. Gemini (모델 제공자) 설치 및 설정

- **설정(Settings)** → **모델 제공자(Model Provider)** (또는 플러그인/API 키 메뉴).
- **Google** / **Gemini** 제공자를 선택 후 **설치** 또는 **설정**.
- [Google AI Studio](https://aistudio.google.com/apikey)에서 발급한 **API 키**를 입력하고 저장.
- 앱의 LLM 노드·질문 분류기 등에서 사용할 **모델**(예: Gemini 2.0 Flash)을 이 제공자에서 선택할 수 있게 된다.

### 2. MinIO S3 Storage Provider 설치 및 설정

- **설정** → **스토리지(Storage)** 또는 **파일 저장소** / **S3 Storage Provider** 관련 메뉴.
- **MinIO** 또는 **S3 호환** 스토리지 제공자를 선택 후 설치·설정.
- 입력 예:
  - **Endpoint**: `http://minio.devops.svc.cluster.local:9000` (클러스터 내부 MinIO)
  - **Access Key ID** / **Secret Access Key**: devops 네임스페이스 MinIO 시크릿의 `rootUser` / `rootPassword` (또는 IAM 키).
  - **Bucket**: `dify` (또는 사용할 버킷명).
  - **Use HTTPS**: 내부 주소면 `false`.
- 저장 후 Dify 파일 업로드·데이터셋이 MinIO에 저장되도록 설정할 수 있다.

위 두 가지를 하지 않으면 **api provider not found**, **스토리지 오류** 등이 발생할 수 있다.

### 3. RAG 커스텀 도구 (CoinTutor RAG / DrillQuiz RAG) — UI에서 등록

앱 워크플로에서 우리 RAG 백엔드를 쓰려면 **Web UI에서** 커스텀 도구를 한 번 등록해야 한다.

1. **도구(Tools)** → **커스텀(Custom)** → **커스텀 도구 만들기**
2. **이름**: `CoinTutor RAG` (또는 `DrillQuiz RAG`)
3. **스키마**: `cointutor-rag-openapi.yaml`(또는 `drillquiz-rag-openapi.yaml`) 파일 내용을 **전부 복사**해 스키마 칸에 **붙여넣기**
4. **인증 방법**: 없음
5. **저장**

이후 워크플로에서 **도구** 노드를 추가할 때 위에서 만든 도구를 선택해 RAG `/query` 를 호출하면 된다.

## 설치 상태 모니터링

| 명령 | 설명 |
|------|------|
| `./status.sh` | Pod/SVC/PVC/Ingress 1회 출력 |
| `./status.sh watch` | Pod 상태 2초 간격 실시간 갱신 (Ctrl+C 종료) |
| `kubectl get pods -n dify -w` | Pod만 실시간 감시 |
| `kubectl rollout status deployment/dify-api -n dify` | api Deployment 롤아웃 완료 대기 |
| `kubectl logs -n dify -l app.kubernetes.io/name=api -f --tail=50` | api 로그 스트리밍 |

필요 시 `KUBECONFIG` 또는 `DIFY_NS`(기본 dify) 환경변수 지정.

## Web UI에서 RAG·챗봇 연결 (7-4)

**전제**: 위 **“설치 후 Web UI에서 필수: 모델 제공자·스토리지”** 에서 **Gemini**와 **MinIO S3 Storage Provider** 설치·설정을 완료한 상태여야 한다.

1. **접속**  
   - **Ingress**: `https://dify.default.<project>.<domain>` 또는 `https://dify.<domain>` (DNS/호스트 설정 후).  
   - **포트포워딩**: 접속 기준 URL이 비어 있으면 리다이렉트/CORS로 화면이 안 열리므로, 포트포워딩만 쓸 때는  
     `DIFY_BASE_URL=http://localhost:8080 bash install.sh` (또는 `reinstall`) 로 설치한 뒤  
     `kubectl port-forward svc/dify 8080:80 -n dify` 실행 후 브라우저에서 **http://localhost:8080** 으로 접속.  
     반드시 **dify** 서비스(proxy)로 포워딩해야 함. **dify-web** 만 포워딩하면 API 주소가 달라 동작하지 않음.  
   최초 로그인 시 관리자 계정 생성.

2. **지식베이스(벡터 DB) 연결**  
   - **설정 → 벡터 데이터베이스**: 이미 values에서 `VECTOR_STORE=qdrant`, `QDRANT_URL`로 설정되어 있으면 Dify가 Qdrant를 사용한다.  
   - **지식베이스 생성**: “지식베이스”에서 새 지식베이스 만들기 → **연동 방식**에서 “API” 또는 “내장 인덱서” 선택 시, Dify가 위 Qdrant에 컬렉션을 생성·사용할 수 있다.  
   - **기존 RAG 컬렉션(rag_docs) 재사용**: Dify가 자체 임베딩으로 새 컬렉션을 만드는 경우가 기본이므로, 기존 `rag_docs`를 그대로 쓰려면 “외부 API” 형태로 RAG 백엔드(`rag-backend`의 `/query`)를 도구로 연결하는 방식이 적합하다.

3. **데이터소스(MinIO/로컬)**  
   - **파일 업로드**: Dify 내 “데이터셋”에서 직접 파일 업로드 시, 설정한 스토리지(로컬 또는 S3/MinIO)에 저장된다.  
   - **MinIO 연동**: 파일을 MinIO 버킷에 두고 Dify가 읽게 하려면, 워크플로/도구에서 “HTTP 요청” 등으로 MinIO URL을 호출하거나, Dify 데이터셋에 “연결” 방식이 지원되면 해당 연결을 설정한다.

4. **질문→답변 플로우**  
   - **챗봇 앱 생성**: “스튜디오”에서 “챗봇” 생성.  
   - **RAG 사용**:  
     - **방법 A**: “지식베이스” 노드 추가 → Dify 내장 지식베이스(위에서 만든 Qdrant 연동) 사용.  
     - **방법 B**: “도구”에 “API” 추가 → RAG 백엔드 URL(`http://rag-backend.rag.svc.cluster.local:8000/query`) 지정해 기존 `rag_docs` 검색 결과를 활용.  
   - 프롬프트에 “지식베이스/도구 결과를 바탕으로 답변하라”고 설정 후 배포.

5. **확인**  
   챗봇에 질문 입력 → RAG 검색 결과가 반영된 답변·인용이 나오는지 확인.

## 산출물 (Phase 7)

- Dify Web UI로 접속 가능한 챗봇
- 벡터 DB(Qdrant) 및 선택 시 MinIO 기반 RAG·데이터소스 연동
- 질문→답변 플로우 및 인용 확인

## 문제 해결 (알려진 이슈)

### Run failed: api provider \<UUID\> not found

**원인**: Dify 재설치(uninstall → install) 또는 DB 초기화 후, 기존 앱/워크플로가 **예전 모델 제공자(API provider) ID**를 참조할 때 발생. 해당 UUID는 새 DB에 없음.

**해결**:

1. **설정 → 모델 제공자(Model Provider)** 에서 사용할 모델(예: Google Gemini)을 **다시 등록** (API 키 입력 후 저장).
2. 오류가 나는 **앱**으로 이동 → **오케스트레이트(워크플로)** 에서 **LLM / 질문 분류기** 등 모델을 쓰는 노드를 열고, **모델** 선택을 방금 등록한 **새 제공자·모델**로 다시 지정 후 저장.
3. 여전히 오류면 해당 앱을 **복제**한 뒤, 복제본 워크플로에서 모든 노드의 모델/제공자를 새로 선택하거나, 앱을 처음부터 다시 구성.

---

## 파일 구성

| 파일 | 내용 |
|------|------|
| `install.sh` | prop 기반 project/domain, Helm repo, values 치환, Dify 설치, Ingress. `reinstall` 인자 시 PVC 삭제 후 재설치 |
| `status.sh` | 설치 상태 모니터링 (pods/svc/pvc/ingress). `watch` 인자 시 실시간 갱신 |
| `values.yaml` | 이미지·API/worker env(Qdrant, S3/MinIO), NFS PVC, PostgreSQL/Redis, Weaviate 비활성화 |
| `dify-ingress.yaml` | Jenkins 스타일 Ingress |
| `cointutor-rag-openapi.yaml` | CoinTutor RAG OpenAPI 스키마 (UI 커스텀 도구 만들기 → 스키마에 붙여넣기) |
| `drillquiz-rag-openapi.yaml` | DrillQuiz RAG OpenAPI 스키마 (위와 동일) |
