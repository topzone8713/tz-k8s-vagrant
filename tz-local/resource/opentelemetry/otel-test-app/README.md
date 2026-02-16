# otel-test-app

Node.js Express 앱으로 OpenTelemetry 트레이싱 테스트용입니다.

## 엔드포인트

| 경로 | 설명 |
|------|------|
| `/` | 앱 정보 |
| `/health` | 헬스 체크 |
| `/trace-test` | 트레이스 생성 (delay 쿼리 파라미터로 지연 ms 지정) |
| `/nested` | 중첩 비동기 작업으로 여러 스팬 생성 |

## 트레이스 테스트 방법

1. 앱 배포 후 트래픽 생성:
   ```bash
   kubectl run curl-test --rm -it --image=curlimages/curl --restart=Never -n nlp -- \
     sh -c 'for i in 1 2 3; do curl -s http://otel-test-app/trace-test?delay=50; done'
   ```

2. Port-forward로 로컬 테스트:
   ```bash
   kubectl port-forward svc/otel-test-app 8080:80 -n nlp
   curl http://localhost:8080/trace-test
   curl http://localhost:8080/nested
   ```

3. Grafana Tempo에서 조회: `serviceName: otel-test-app`
