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
    echo -e "${YELLOW}다른 라벨로 시도합니다...${NC}"
    POD_NAME=$(kubectl get pods -n devops-dev | grep postgres | awk '{print $1}' | head -n 1)
    
    if [ -z "$POD_NAME" ]; then
        echo -e "${RED}❌ PostgreSQL Pod를 찾을 수 없습니다.${NC}"
        echo "사용 가능한 Pod 목록:"
        kubectl get pods -n devops-dev
        exit 1
    fi
fi

echo -e "${GREEN}✓ Pod 발견: $POD_NAME${NC}"

# 기존 포트포워딩 확인 (이미 54486으로 되어 있음)
if lsof -ti:54486 > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 포트 54486이 이미 포워딩되어 있습니다.${NC}"
    PF_PID=$(lsof -ti:54486)
    echo ""
    echo -e "${GREEN}연결 정보:${NC}"
    echo "  Host: localhost"
    echo "  Port: 54486"
    echo "  Database: drillquiz"
    echo "  User: admin"
else
    echo -e "${YELLOW}포트 포워딩을 시작합니다...${NC}"
    kubectl port-forward -n devops-dev $POD_NAME 54486:5432 > /dev/null 2>&1 &
    PF_PID=$!
    
    # 포트 포워딩 대기
    sleep 2
    
    if ps -p $PF_PID > /dev/null; then
        echo -e "${GREEN}✓ 포트 포워딩 성공 (PID: $PF_PID)${NC}"
        echo ""
        echo -e "${GREEN}연결 정보:${NC}"
        echo "  Host: localhost"
        echo "  Port: 54486"
        echo "  Database: drillquiz"
        echo "  User: admin"
    else
        echo -e "${RED}❌ 포트 포워딩 실패${NC}"
        exit 1
    fi
fi

if [ ! -z "$PF_PID" ]; then
    echo ""
    echo -e "${YELLOW}종료하려면: ./scripts/dev_db_disconnect.sh${NC}"
    echo -e "${YELLOW}또는: kill $PF_PID${NC}"
    echo ""
    
    # .env 파일 생성 제안
    if [ ! -f .env.local ]; then
        echo -e "${YELLOW}💡 .env.local 파일을 생성하시겠습니까? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            cat > .env.local << 'EOF'
USE_POSTGRES=true
POSTGRES_HOST=localhost
POSTGRES_PORT=54486
POSTGRES_DB=drillquiz
POSTGRES_USER=admin
POSTGRES_PASSWORD=

DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1
SECRET_KEY=dev-secret-key-change-in-production

REDIS_URL=redis://localhost:6379/1
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/2
EOF
            echo -e "${GREEN}✓ .env.local 파일이 생성되었습니다.${NC}"
            echo -e "${YELLOW}⚠️  POSTGRES_PASSWORD를 입력해주세요!${NC}"
            echo ""
            echo "비밀번호 확인 명령어:"
            echo "kubectl get secret -n devops-dev devops-postgres-postgresql -o jsonpath='{.data.postgres-password}' | base64 -d"
        fi
    fi
    
    # PID 파일 저장 (새로 시작한 경우만)
    if ps -p $PF_PID > /dev/null 2>&1; then
        echo $PF_PID > .dev_db_pid
    fi
fi

echo ""
echo -e "${GREEN}🚀 개발 환경 준비 완료!${NC}"
    echo ""
echo ""
echo "다음 명령어로 Django 서버를 시작하세요:"
echo "  source .env.local"
echo "  export \$(cat .env.local | xargs)"
echo "  source venv/bin/activate"
echo "  python manage.py runserver"

