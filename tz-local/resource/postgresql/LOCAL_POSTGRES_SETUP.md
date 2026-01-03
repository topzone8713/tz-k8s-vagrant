# DrillQuiz 로컬 PostgreSQL 개발 환경 설정

## 📋 개요

이 문서는 로컬 개발 환경에서 Kubernetes devops-dev 네임스페이스의 PostgreSQL 데이터베이스를 사용하는 방법을 설명합니다.

**⚠️ 중요**: 개발 환경에서도 SQLite를 사용하지 않고 PostgreSQL을 사용하는 것을 권장합니다. 하지만 필요시 환경 파일(`env`)에서 `USE_POSTGRES=false`로 설정하여 SQLite를 사용할 수도 있습니다.

**작성일**: 2025-12-02  
**버전**: 1.2

---

## 🎯 구성 개요

```
로컬 개발 환경
    │
    ├─> 방법 1: 외부 접속 (NodePort) - 권장
    │       │
    │       └─> db-dev.topzone.me:30432
    │               │
    │               └─> devops-dev namespace
    │                       │
    │                       └─> PostgreSQL Pod
    │
    ├─> 방법 2: kubectl port-forward (대안)
    │       │
    │       └─> localhost:54486
    │               │
    │               └─> devops-dev namespace
    │                       │
    │                       └─> PostgreSQL Pod
    │
    └─> Django 애플리케이션
            │
            └─> PostgreSQL 연결 (USE_POSTGRES=true)
```

---

## 🔧 사전 요구사항

### 1. kubectl 설정

```bash
# kubeconfig 설정
ex) export KUBECONFIG=~/.kube/topzone.iptime.org.config

# 네임스페이스 확인
kubectl get namespaces

# devops-dev 네임스페이스의 Pod 확인
kubectl get pods -n devops-dev
```

### 2. PostgreSQL Pod 확인

```bash
# PostgreSQL Pod 찾기
kubectl get pods -n devops-dev | grep postgres

# 예상 출력:
# devops-postgres-postgresql-0   1/1     Running   0          10d
```

### 3. 데이터베이스 정보 확인

```bash
# Secret에서 비밀번호 확인
kubectl get secret -n devops-dev devops-postgres-postgresql -o jsonpath='{.data.postgres-password}' | base64 -d
echo

# 기본 정보:
# 방법 1 (외부 접속): Host: db-dev.topzone.me, Port: 30432
# 방법 2 (포트 포워딩): Host: localhost, Port: 54486
# Database: drillquiz
# User: admin
# Password: DevOps!323 (또는 위에서 확인한 비밀번호)
```

---

## 🔄 데이터베이스 선택 (PostgreSQL vs SQLite)

환경 파일(`env`)에서 `USE_POSTGRES` 값을 변경하여 데이터베이스를 전환할 수 있습니다.

### PostgreSQL 사용 (권장)

```bash
# env 파일에서
USE_POSTGRES=true
POSTGRES_HOST=db-dev.topzone.me
POSTGRES_PORT=30432
POSTGRES_DB=drillquiz
POSTGRES_USER=admin
POSTGRES_PASSWORD=DevOps!323
```

### SQLite 사용 (레거시 지원)

```bash
# env 파일에서
USE_POSTGRES=false
# PostgreSQL 설정은 무시됨
```

**⚠️ 주의**: SQLite는 레거시 지원용이며, 개발 환경에서는 PostgreSQL 사용을 권장합니다.

---

## 🚀 데이터베이스 접속 방법

### 방법 1: 외부 접속 (NodePort) - 권장 ⭐

개발 환경에서도 PostgreSQL을 직접 사용합니다. 외부 접속을 통해 개발 DB에 연결합니다.

```bash
# 환경 변수 설정
export USE_POSTGRES=true
export POSTGRES_HOST=db-dev.topzone.me
export POSTGRES_PORT=30432
export POSTGRES_DB=drillquiz
export POSTGRES_USER=admin
export POSTGRES_PASSWORD='DevOps!323'

# Django 연결 테스트
python manage.py check --database default

# Django Shell로 테스트
python manage.py shell -c "from django.db import connection; connection.ensure_connection(); print('✅ 연결 성공')"
```

**장점:**
- 포트 포워딩 불필요
- 별도 스크립트 실행 불필요
- 즉시 사용 가능

### 방법 2: 포트 포워딩 (대안)

포트 포워딩을 사용하는 경우:

```bash
# 포트 포워딩 확인
lsof -i:54486

# 연결 정보
# Host: localhost
# Port: 54486
# Database: drillquiz
# User: admin
```

**새로운 포트 포워딩 (필요 시):**

```bash
# 다른 로컬 포트로 포워딩
kubectl port-forward -n devops-dev svc/devops-postgres-postgresql 54486:5432
```

### 방법 3: 자동화 스크립트 사용

`scripts/dev_db_connect.sh` 스크립트를 사용하세요 (아래 참조)

---

## 🌐 외부 접속 (NodePort 서비스)

### 개요

PostgreSQL을 외부에서 직접 접속할 수 있도록 NodePort 서비스를 통해 노출할 수 있습니다.

**⚠️ 보안 주의사항**: 
- 개발/테스트 환경에서만 사용 권장
- 프로덕션 환경에서는 VPN, bastion host, 또는 port-forward 사용 권장
- 방화벽 규칙으로 특정 IP만 허용하는 것을 권장

### NodePort 서비스 배포

```bash
# PostgreSQL 외부 접속 서비스 배포
kubectl apply -f ci/postgres-dev.yaml

# 서비스 확인
kubectl get svc -n devops-dev devops-dev-postgres-postgresql-external
```

### 접속 정보

- **서비스명**: `devops-dev-postgres-postgresql-external`
- **네임스페이스**: `devops-dev`
- **외부 포트**: `30432` (NodePort)
- **내부 포트**: `5432`
- **데이터베이스**: `drillquiz`
- **사용자**: `admin`
- **비밀번호**: `DevOps!323` (Secret에서 확인 가능)

### 접속 방법

#### 방법 1: 도메인을 사용한 접속 (권장)

```bash
# 도메인을 사용한 접속
PGPASSWORD='DevOps!323' psql -h db-dev.topzone.me -p 30432 -U admin -d drillquiz

# 또는 환경 변수로 설정
export PGPASSWORD='DevOps!323'
psql -h db-dev.topzone.me -p 30432 -U admin -d drillquiz
```

#### 방법 2: IP 주소를 사용한 접속

```bash
# Node IP 확인
kubectl get nodes -o wide

# Worker 노드 IP 사용 (권장)
# 예: kube-node-1 (192.168.0.63) 또는 kube-node-2 (192.168.0.62)
PGPASSWORD='DevOps!323' psql -h 192.168.0.63 -p 30432 -U admin -d drillquiz

# 또는 외부 IP 사용 (DNS가 설정된 경우)
PGPASSWORD='DevOps!323' psql -h 183.96.137.87 -p 30432 -U admin -d drillquiz
```

### 접속 테스트

```bash
# PostgreSQL 버전 확인
PGPASSWORD='DevOps!323' psql -h db-dev.topzone.me -p 30432 -U admin -d drillquiz -c "SELECT version();"

# 데이터베이스 정보 확인
PGPASSWORD='DevOps!323' psql -h db-dev.topzone.me -p 30432 -U admin -d drillquiz -c "SELECT current_database(), current_user;"

# 테이블 목록 확인
PGPASSWORD='DevOps!323' psql -h db-dev.topzone.me -p 30432 -U admin -d drillquiz -c "\dt"
```

### DNS 설정

도메인 `db-dev.topzone.me`이 노드의 외부 IP로 리다이렉트되도록 DNS 설정이 필요합니다.

```bash
# DNS 확인
nslookup db-dev.topzone.me
# 또는
dig db-dev.topzone.me +short

# 예상 결과: 183.96.137.87 (노드의 외부 IP)
```

### 보안 강화 (선택사항)

#### IP 제한 설정

`ci/postgres-dev.yaml` 파일에서 특정 IP만 허용하도록 설정할 수 있습니다:

```yaml
spec:
  externalIPs:
    - "YOUR_IP_ADDRESS"  # 허용할 IP 주소
```

#### 방화벽 규칙

Kubernetes 노드의 방화벽에서 30432 포트를 특정 IP만 허용하도록 설정:

```bash
# 예시 (Ubuntu/Debian)
sudo ufw allow from YOUR_IP_ADDRESS to any port 30432
```

---

## 🗄️ 데이터베이스 초기화

### 1. 스키마 생성

```bash
# 포트 포워딩이 실행 중인 상태에서
psql -h localhost -p 54486 -U admin -d postgres -f scripts/init_db_schema.sql

# 비밀번호 입력: (Secret에서 확인한 비밀번호)
```

### 2. Django 마이그레이션

**방법 1: 외부 접속 (권장)**

```bash
# Python 가상환경 활성화
source venv/bin/activate

# 환경 변수 설정
export USE_POSTGRES=true
export POSTGRES_HOST=db-dev.topzone.me
export POSTGRES_PORT=30432
export POSTGRES_DB=drillquiz
export POSTGRES_USER=admin
export POSTGRES_PASSWORD='DevOps!323'

# 마이그레이션 실행
python manage.py makemigrations
python manage.py migrate
```

**방법 2: 포트 포워딩 (대안)**

```bash
# Python 가상환경 활성화
source venv/bin/activate

# 환경 변수 설정
export USE_POSTGRES=true
export POSTGRES_HOST=localhost
export POSTGRES_PORT=54486
export POSTGRES_DB=drillquiz
export POSTGRES_USER=admin
export POSTGRES_PASSWORD='DevOps!323'

# 마이그레이션 실행
python manage.py makemigrations
python manage.py migrate
```

### 3. 초기 데이터 로드

```bash
# 슈퍼유저 생성
python manage.py createsuperuser

# 샘플 데이터 로드 (선택사항)
python manage.py loaddata fixtures/initial_data.json
```

---

## ⚙️ Django 설정

### settings.py 설정

**⚠️ 중요**: 개발 환경에서도 SQLite를 사용하지 않고 PostgreSQL을 사용합니다.

`drillquiz/settings.py`는 기본적으로 PostgreSQL을 사용하도록 설정되어 있습니다:

```python
# drillquiz/settings.py

# Database
# ⚠️ 중요: 개발 환경에서도 SQLite를 사용하지 않고 PostgreSQL을 사용합니다.
USE_POSTGRES = os.environ.get('USE_POSTGRES', 'true').lower() == 'true'

# PostgreSQL 사용 (기본값: true)
# 개발 환경에서는 Kubernetes devops-dev 네임스페이스의 PostgreSQL을 사용
# 또는 외부 접속: db-dev.topzone.me:30432
if USE_POSTGRES:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.postgresql',
            'NAME': os.environ.get('POSTGRES_DB', 'drillquiz'),
            'USER': os.environ.get('POSTGRES_USER', 'admin'),
            'PASSWORD': os.environ.get('POSTGRES_PASSWORD', 'DevOps!323'),
            'HOST': os.environ.get('POSTGRES_HOST', 'db-dev.topzone.me'),
            'PORT': os.environ.get('POSTGRES_PORT', '30432'),
            'OPTIONS': {
                'connect_timeout': 10,
            },
        }
    }
```

**기본값:**
- `USE_POSTGRES=true` (기본값)
- `POSTGRES_HOST=db-dev.topzone.me` (외부 접속)
- `POSTGRES_PORT=30432` (NodePort)
- `POSTGRES_DB=drillquiz`
- `POSTGRES_USER=admin`
- `POSTGRES_PASSWORD=DevOps!323`

### .env 파일 설정

**방법 1: 외부 접속 (권장)**

```bash
# .env.local (로컬 개발용 - 외부 접속)
USE_POSTGRES=true
POSTGRES_HOST=db-dev.topzone.me
POSTGRES_PORT=30432
POSTGRES_DB=drillquiz
POSTGRES_USER=admin
POSTGRES_PASSWORD=DevOps!323

# Django 설정
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1
SECRET_KEY=your-secret-key-for-development

# Redis (선택사항)
REDIS_URL=redis://localhost:6379/1
CELERY_BROKER_URL=redis://localhost:6379/0
```

**방법 2: 포트 포워딩 (대안)**

```bash
# .env.local (로컬 개발용 - 포트 포워딩)
USE_POSTGRES=true
POSTGRES_HOST=localhost
POSTGRES_PORT=54486
POSTGRES_DB=drillquiz
POSTGRES_USER=admin
POSTGRES_PASSWORD=DevOps!323

# Django 설정
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1
SECRET_KEY=your-secret-key-for-development
```

---

## 🔌 연결 테스트

### psql로 직접 연결

```bash
# 연결 테스트
psql -h localhost -p 54486 -U admin -d drillquiz

# SQL 쿼리 실행
drillquiz=> \dt  # 테이블 목록
drillquiz=> \d quiz  # 특정 테이블 스키마
drillquiz=> SELECT COUNT(*) FROM quiz_question;  # 데이터 확인
drillquiz=> \q  # 종료
```

### Python으로 연결 테스트

**방법 1: 외부 접속 (권장)**

```python
# test_db_connection.py
import psycopg2
import os

conn = psycopg2.connect(
    host=os.getenv('POSTGRES_HOST', 'db-dev.topzone.me'),
    port=os.getenv('POSTGRES_PORT', '30432'),
    dbname=os.getenv('POSTGRES_DB', 'drillquiz'),
    user=os.getenv('POSTGRES_USER', 'admin'),
    password=os.getenv('POSTGRES_PASSWORD', 'DevOps!323')
)

cursor = conn.cursor()
cursor.execute('SELECT version();')
version = cursor.fetchone()
print(f'PostgreSQL version: {version[0]}')

cursor.execute('SELECT COUNT(*) FROM quiz_question;')
count = cursor.fetchone()
print(f'Question count: {count[0]}')

cursor.close()
conn.close()
```

**방법 2: 포트 포워딩 (대안)**

```python
# test_db_connection.py
import psycopg2
import os

conn = psycopg2.connect(
    host=os.getenv('POSTGRES_HOST', 'localhost'),
    port=os.getenv('POSTGRES_PORT', '54486'),
    dbname=os.getenv('POSTGRES_DB', 'drillquiz'),
    user=os.getenv('POSTGRES_USER', 'admin'),
    password=os.getenv('POSTGRES_PASSWORD', 'DevOps!323')
)
```

### Django shell로 테스트

**방법 1: 외부 접속 (권장)**

```bash
# 환경 변수 설정
export USE_POSTGRES=true
export POSTGRES_HOST=db-dev.topzone.me
export POSTGRES_PORT=30432
export POSTGRES_DB=drillquiz
export POSTGRES_USER=admin
export POSTGRES_PASSWORD='DevOps!323'

# Django shell 실행
python manage.py shell

>>> from django.db import connection
>>> connection.ensure_connection()
>>> print(connection.settings_dict)
>>> 
>>> from backend.models import Tutor
>>> Tutor.objects.count()
3
>>> 
>>> exit()
```

**방법 2: 포트 포워딩 (대안)**

```bash
# 환경 변수 설정
export USE_POSTGRES=true
export POSTGRES_HOST=localhost
export POSTGRES_PORT=54486
export POSTGRES_DB=drillquiz
export POSTGRES_USER=admin
export POSTGRES_PASSWORD='DevOps!323'

# Django shell 실행
python manage.py shell
```

---

## 📜 편의 스크립트

### scripts/dev_db_connect.sh

```bash
#!/bin/bash

# DrillQuiz 개발 DB 연결 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}DrillQuiz 개발 DB 연결${NC}"
echo "======================================"

# kubeconfig 확인
if [ ! -f ~/.kube/topzone.iptime.org.config ]; then
    echo -e "${RED}❌ kubeconfig 파일을 찾을 수 없습니다.${NC}"
    exit 1
fi

export KUBECONFIG=~/.kube/topzone.iptime.org.config

# PostgreSQL Pod 확인
echo -e "${YELLOW}PostgreSQL Pod 확인 중...${NC}"
POD_NAME=$(kubectl get pods -n devops-dev -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD_NAME" ]; then
    echo -e "${RED}❌ PostgreSQL Pod를 찾을 수 없습니다.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Pod 발견: $POD_NAME${NC}"

# 포트 포워딩 확인
if lsof -ti:5432 > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  포트 5432가 이미 사용 중입니다.${NC}"
    echo -e "${YELLOW}   기존 프로세스를 종료하시겠습니까? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        lsof -ti:5432 | xargs kill -9
        echo -e "${GREEN}✓ 기존 프로세스 종료됨${NC}"
    else
        echo -e "${RED}포트 포워딩을 중단합니다.${NC}"
        exit 1
    fi
fi

# 포트 포워딩 시작
echo -e "${YELLOW}포트 포워딩 시작 중...${NC}"
kubectl port-forward -n devops-dev $POD_NAME 5432:5432 > /dev/null 2>&1 &
PF_PID=$!

# 포트 포워딩 대기
sleep 2

if ps -p $PF_PID > /dev/null; then
    echo -e "${GREEN}✓ 포트 포워딩 성공 (PID: $PF_PID)${NC}"
    echo ""
    echo -e "${GREEN}연결 정보:${NC}"
    echo "  Host: localhost"
    echo "  Port: 5432"
    echo "  Database: drillquiz"
    echo "  User: admin"
    echo ""
    echo -e "${YELLOW}종료하려면: kill $PF_PID${NC}"
    echo ""
    
    # .env 파일 생성 제안
    if [ ! -f .env.local ]; then
        echo -e "${YELLOW}💡 .env.local 파일을 생성하시겠습니까? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            cat > .env.local << EOF
USE_POSTGRES=true
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=drillquiz
POSTGRES_USER=admin
POSTGRES_PASSWORD=

DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1
EOF
            echo -e "${GREEN}✓ .env.local 파일이 생성되었습니다.${NC}"
            echo -e "${YELLOW}⚠️  POSTGRES_PASSWORD를 입력해주세요!${NC}"
        fi
    fi
    
    # PID 파일 저장
    echo $PF_PID > .dev_db_pid
    
else
    echo -e "${RED}❌ 포트 포워딩 실패${NC}"
    exit 1
fi
```

### scripts/dev_db_disconnect.sh

```bash
#!/bin/bash

# 포트 포워딩 종료 스크립트

if [ -f .dev_db_pid ]; then
    PID=$(cat .dev_db_pid)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID
        echo "✓ 포트 포워딩 종료됨 (PID: $PID)"
    else
        echo "⚠️  프로세스가 이미 종료되었습니다."
    fi
    rm .dev_db_pid
else
    echo "❌ .dev_db_pid 파일을 찾을 수 없습니다."
    echo "수동으로 종료하려면: lsof -ti:5432 | xargs kill"
fi
```

---

## 🛠️ 개발 워크플로우

### 1. 개발 시작 (외부 접속 방식 - 권장)

```bash
# 1. 환경 변수 설정
export USE_POSTGRES=true
export POSTGRES_HOST=db-dev.topzone.me
export POSTGRES_PORT=30432
export POSTGRES_DB=drillquiz
export POSTGRES_USER=admin
export POSTGRES_PASSWORD='DevOps!323'

# 2. Python 가상환경 활성화
source venv/bin/activate

# 3. Django 서버 시작
python manage.py runserver

# 4. 프론트엔드 서버 시작 (별도 터미널)
npm run serve
```

### 1-1. 개발 시작 (포트 포워딩 방식 - 대안)

```bash
# 1. 개발 DB 연결
./scripts/dev_db_connect.sh

# 2. 환경 변수 설정
export USE_POSTGRES=true
export POSTGRES_HOST=localhost
export POSTGRES_PORT=54486
export POSTGRES_DB=drillquiz
export POSTGRES_USER=admin
export POSTGRES_PASSWORD='DevOps!323'

# 3. Python 가상환경 활성화
source venv/bin/activate

# 4. Django 서버 시작
python manage.py runserver

# 5. 프론트엔드 서버 시작 (별도 터미널)
npm run serve
```

### 2. 개발 종료

```bash
# Django/Vue 서버 종료 (Ctrl+C)

# 포트 포워딩 종료
./scripts/dev_db_disconnect.sh

# 또는
kill $(cat .dev_db_pid)
```

---

## 🔍 문제 해결

### 문제 1: 연결 시간 초과

```bash
# 증상
psql: error: connection to server at "localhost" (::1), port 5432 failed: 
Operation timed out

# 해결
1. 포트 포워딩이 실행 중인지 확인
   ps aux | grep port-forward

2. Pod 상태 확인
   kubectl get pods -n devops-dev

3. 포트 포워딩 재시작
   ./scripts/dev_db_disconnect.sh
   ./scripts/dev_db_connect.sh
```

### 문제 2: 인증 실패

```bash
# 증상
psql: error: connection to server at "localhost", port 5432 failed: 
FATAL: password authentication failed for user "admin"

# 해결
1. 비밀번호 다시 확인
   kubectl get secret -n devops-dev devops-postgres-postgresql \
     -o jsonpath='{.data.postgres-password}' | base64 -d

2. .env.local 파일 업데이트
   POSTGRES_PASSWORD=올바른-비밀번호
```

### 문제 3: 포트 충돌

```bash
# 증상
Error: listen tcp :54486: bind: address already in use

# 해결
1. 사용 중인 프로세스 확인
   lsof -i:54486

2. 기존 포트포워딩이 이미 실행 중이면 그대로 사용
   (개발 환경에서 이미 54486으로 포워딩되어 있음)

3. 다른 포트 사용이 필요한 경우
   kubectl port-forward -n devops-dev svc/devops-postgres-postgresql 15432:5432
   # .env.local의 POSTGRES_PORT=15432로 변경
```

### 문제 4: 테이블이 없음

```bash
# 증상
relation "quiz_question" does not exist

# 해결
1. 스키마 초기화
   psql -h localhost -p 5432 -U admin -d drillquiz -f scripts/init_db_schema.sql

2. Django 마이그레이션 실행
   python manage.py migrate
```

---

## 📊 데이터베이스 관리

### 백업

```bash
# 로컬 포트포워딩을 통한 백업 (권장)
pg_dump -h localhost -p 54486 -U admin drillquiz > backup_$(date +%Y%m%d_%H%M%S).sql

# 특정 테이블만 백업
pg_dump -h localhost -p 54486 -U admin -t quiz_question drillquiz > quiz_backup.sql

# 또는 kubectl을 통한 직접 백업
kubectl exec -n devops-dev devops-postgres-postgresql-0 -- \
  pg_dump -U admin drillquiz > backup_$(date +%Y%m%d_%H%M%S).sql
```

### 복원

```bash
# 로컬 포트포워딩을 통한 복원 (권장)
psql -h localhost -p 54486 -U admin drillquiz < backup_20251202_120000.sql

# 또는 kubectl을 통한 직접 복원
kubectl exec -i -n devops-dev devops-postgres-postgresql-0 -- \
  psql -U admin drillquiz < backup_20251202_120000.sql
```

### 데이터 초기화

```bash
# ⚠️  경고: 모든 데이터가 삭제됩니다!

# Django를 통한 초기화
python manage.py flush --no-input

# 또는 PostgreSQL에서 직접
psql -h localhost -p 54486 -U admin -d drillquiz
drillquiz=> DROP SCHEMA public CASCADE;
drillquiz=> CREATE SCHEMA public;
drillquiz=> \q

# 스키마 재생성
psql -h localhost -p 54486 -U admin -d drillquiz -f scripts/init_db_schema.sql
python manage.py migrate
```

---

## 🔐 보안 고려사항

1. **비밀번호 관리**
   - `.env.local` 파일을 절대 Git에 커밋하지 마세요
   - `.gitignore`에 `.env*` 패턴이 포함되어 있는지 확인

2. **포트 포워딩**
   - 개발 완료 후 포트 포워딩을 반드시 종료하세요
   - 장시간 포트 포워딩 유지 금지

3. **데이터베이스 접근**
   - 프로덕션 데이터베이스는 절대 로컬에서 직접 접근하지 마세요
   - 개발 DB(devops-dev)만 사용하세요

---

## 📚 참고 자료

- PostgreSQL 공식 문서: https://www.postgresql.org/docs/15/
- Django PostgreSQL 설정: https://docs.djangoproject.com/en/4.2/ref/databases/#postgresql-notes
- kubectl port-forward: https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/

**문서 버전**: 1.2  
**최종 업데이트**: 2025-12-07  
**작성자**: DrillQuiz Development Team

## 📝 변경 이력

### v1.2 (2025-12-07)
- 환경 파일(`env`)에서 `USE_POSTGRES` 값으로 PostgreSQL/SQLite 전환 가능하도록 명확화
- SQLite 사용 방법 추가 (레거시 지원)
- 데이터베이스 선택 섹션 추가

### v1.1 (2025-12-07)
- 개발 환경에서도 SQLite를 사용하지 않고 PostgreSQL을 사용하도록 변경
- 외부 접속(NodePort) 방법 추가 및 권장
- 기본값을 PostgreSQL로 변경 (`USE_POSTGRES=true`)
- 접속 방법 2가지 제공: 외부 접속(권장) 및 포트 포워딩(대안)

### v1.0 (2025-12-02)
- 초기 문서 작성

