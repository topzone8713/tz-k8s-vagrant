#!/bin/bash

# DrillQuiz 개발 DB 연결 종료 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}DrillQuiz 개발 DB 연결 종료${NC}"
echo "======================================"

if [ -f .dev_db_pid ]; then
    PID=$(cat .dev_db_pid)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID
        echo -e "${GREEN}✓ 포트 포워딩 종료됨 (PID: $PID)${NC}"
    else
        echo -e "${YELLOW}⚠️  프로세스가 이미 종료되었습니다.${NC}"
    fi
    rm .dev_db_pid
    echo -e "${GREEN}✓ PID 파일 삭제됨${NC}"
else
    echo -e "${YELLOW}⚠️  .dev_db_pid 파일을 찾을 수 없습니다.${NC}"
    echo ""
    echo "포트 54486을 사용하는 프로세스 확인:"
    if lsof -ti:54486 > /dev/null 2>&1; then
        lsof -i:54486
        echo ""
        echo -e "${YELLOW}수동으로 종료하시겠습니까? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            lsof -ti:54486 | xargs kill -9
            echo -e "${GREEN}✓ 프로세스 종료됨${NC}"
        fi
    else
        echo -e "${GREEN}✓ 포트 54486은 사용 중이지 않습니다.${NC}"
    fi
fi

echo ""
echo -e "${GREEN}개발 DB 연결이 종료되었습니다.${NC}"

