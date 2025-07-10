#!/bin/bash

START_TIME=$(date +%s)

# 기본 변수 (인자로 컨테이너 이름 받기)
WEBGOAT_CONTAINER="${1:-webgoat-test}"
ZAP_HOST="127.0.0.1"
ZAP_PORT="8090"
USERNAME="test12"
PASSWORD="test12"
COOKIE_TXT="cookie.txt"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_JSON="$HOME/zap_scan_${TIMESTAMP}_report.json"

# ① 컨테이너 IP 조회
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$WEBGOAT_CONTAINER")
if [ -z "$CONTAINER_IP" ]; then
  echo "[-] 컨테이너 '$WEBGOAT_CONTAINER' 의 IP를 가져올 수 없습니다."
  exit 1
fi
HOST="http://${CONTAINER_IP}:8080"
echo "[*] ZAP 스캔 대상 호스트: $HOST"

# ② 애플리케이션 준비 대기 (초기 15초 + 로그인 페이지 헬스체크)
echo "[0] 초기 대기 15초..."
sleep 15

echo "[0] 로그인 페이지 준비 확인 시작..."
for i in $(seq 1 10); do
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$HOST/WebGoat/login")
  if [ "$HTTP_CODE" = "200" ]; then
    echo "[+] 로그인 페이지 준비 완료!"
    break
  else
    echo "  [$i] 준비 안됨 (HTTP $HTTP_CODE). 10초 후 재시도..."
    sleep 10
  fi
done

if [ "$HTTP_CODE" != "200" ]; then
  echo "[-] 로그인 페이지가 10회 재시도 후에도 준비되지 않았습니다."
  exit 1
fi

# ③ 회원가입 → 로그인
echo "[1] 회원가입 요청..."
curl -s -i -c "$COOKIE_TXT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$USERNAME&password=$PASSWORD&matchingPassword=$PASSWORD&agree=agree" \
  "$HOST/WebGoat/register.mvc" > /dev/null

echo "[2] 로그인 시도..."
curl -s -i -c "$COOKIE_TXT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$USERNAME&password=$PASSWORD" \
  "$HOST/WebGoat/login" > /dev/null

COOKIE=$(grep JSESSIONID "$COOKIE_TXT" | awk '{print $7}')
if [ -n "$COOKIE" ]; then
  echo "[+] 로그인 성공 - 쿠키: $COOKIE"
else
  echo "[-] 로그인 실패"
  exit 1
fi

# ④ ZAP 데몬 기동/대기
if pgrep -f zap.sh > /dev/null; then
  echo "[3-0] 기존 ZAP 종료..."
  pkill -f zap.sh
  sleep 5
fi
echo "[3] ZAP 데몬 시작..."
zap.sh -daemon -host "$ZAP_HOST" -port "$ZAP_PORT" -config api.disablekey=true > /dev/null 2>&1 &
for i in {1..60}; do
  curl -s "http://$ZAP_HOST:$ZAP_PORT" > /dev/null && { echo "[+] ZAP 준비 완료"; break; }
  sleep 1
done

# ⑤ 인증 쿠키 설정 & 초기 페이지 접근
echo "[4] ZAP에 인증 쿠키 설정..."
curl -s "http://$ZAP_HOST:$ZAP_PORT/JSON/replacer/action/addRule/?description=authcookie&enabled=true&matchType=REQ_HEADER&matchRegex=false&matchString=Cookie&replacement=JSESSIONID=$COOKIE" > /dev/null

echo "[5] 인증 페이지 접근..."
curl -s "http://$ZAP_HOST:$ZAP_PORT/JSON/core/action/accessUrl/?url=$HOST/WebGoat/start.mvc" > /dev/null

# ⑥ Spider 스캔
echo "[6] Spider 스캔 시작..."
SPIDER_ID=$(curl -s "http://$ZAP_HOST:$ZAP_PORT/JSON/spider/action/scan/?url=$HOST/WebGoat/start.mvc" | jq -r .scan)
while true; do
  STATUS=$(curl -s "http://$ZAP_HOST:$ZAP_PORT/JSON/spider/view/status/?scanId=$SPIDER_ID" | jq -r .status)
  echo "  - Spider 진행률: $STATUS%"
  [ "$STATUS" == "100" ] && break
  sleep 2
done

# ⑦ Active 스캔
echo "[7] Active 스캔 시작..."
SCAN_ID=$(curl -s "http://$ZAP_HOST:$ZAP_PORT/JSON/ascan/action/scan/?url=$HOST/WebGoat/start.mvc" | jq -r .scan)
while true; do
  STATUS=$(curl -s "http://$ZAP_HOST:$ZAP_PORT/JSON/ascan/view/status/?scanId=$SCAN_ID" | jq -r .status)
  echo "  - Active 진행률: $STATUS%"
  [ "$STATUS" == "100" ] && break
  sleep 5
done

# ⑧ Passive 스캔 대기
echo "[7-1] Passive 스캔 대기 중..."
while true; do
  REMAIN=$(curl -s "http://$ZAP_HOST:$ZAP_PORT/JSON/pscan/view/recordsToScan/" | jq -r .recordsToScan)
  echo "  - 남은 레코드: $REMAIN"
  [ "$REMAIN" -eq 0 ] && break
  sleep 2
done

# ⑨ JSON 리포트 저장
echo "[8] JSON 리포트 저장..."
curl -s "http://$ZAP_HOST:$ZAP_PORT/OTHER/core/other/jsonreport/" -o "$REPORT_JSON"
if [ -s "$REPORT_JSON" ]; then
  echo "[+] 리포트: $REPORT_JSON"
else
  echo "[-] 리포트 생성 실패"
  exit 1
fi

# 종료 및 수행 시간 출력
pkill -f zap.sh || true
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
printf "[+] 전체 수행 시간: %d분 %d초\n" $((ELAPSED/60)) $((ELAPSED%60))

# 📁 가장 최신 리포트를 zap_test.json 으로 복사 (Jenkins에서 가져갈 수 있도록)
LATEST_REPORT=$(ls -t ~/zap_scan_*_report.json | head -n 1)
cp "$LATEST_REPORT" ~/zap_test.json
