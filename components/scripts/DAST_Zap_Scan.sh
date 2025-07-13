#!/bin/bash

# nohup 실행 시 안정성을 위한 설정
set -e
set -o pipefail

# 작업 디렉터리를 Jenkins workspace로 설정
WORKSPACE_DIR="/home/ec2-user/jenkins-agent/workspace/DAST_Test"
cd "$WORKSPACE_DIR"

# 로그 파일 설정 (nohup.out 대신 명시적 로그)
LOG_FILE="zap_bg_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "🚀 스크립트 시작: $(date)"
echo "📁 작업 디렉터리: $(pwd)"
echo "📝 로그 파일: $LOG_FILE"

# dot.env 파일 위치 확인 및 로드
if [ -f "components/dot.env" ]; then
    source components/dot.env
    echo "✅ dot.env 로드 완료"
elif [ -f "dot.env" ]; then
    source dot.env
    echo "✅ dot.env 로드 완료 (루트에서)"
else
    echo "🚨 Error: dot.env 파일을 찾을 수 없습니다"
    echo "현재 디렉터리: $(pwd)"
    echo "파일 목록:"
    ls -la
    echo "components 디렉터리:"
    ls -la components/ 2>/dev/null || echo "components 디렉터리가 없습니다"
    exit 1
fi

# 기본값
CONTAINER_NAME="${BUILD_TAG}"
IMAGE_TAG="${DYNAMIC_IMAGE_TAG}"
ZAP_SCRIPT="${ZAP_SCRIPT:-zap_scan.sh}"
ZAP_BIN="${ZAP_BIN:-$HOME/zap/zap.sh}" # zap.sh 실행 경로
startpage="${1:-}"

echo "🔧 ECR_REPO: $ECR_REPO"
echo "DEBUG: 변수 설정 완료"

# 포트 찾기
port=""
zap_port=""
for try_port in {8081..8089}; do
  echo "[DEBUG] 시도 중: $try_port"
  set +e
  lsof_stdout=$(lsof -iTCP:$try_port -sTCP:LISTEN -n -P 2>/dev/null)
  lsof_exit_code=$?
  set -e
  echo "[DEBUG] lsof 종료 코드: $lsof_exit_code"
  echo "[DEBUG] lsof 출력: $lsof_stdout"
  
  # "포트 사용 안 함" 상황 → 정상 처리
  if [ $lsof_exit_code -ne 0 ] && [ -z "$lsof_stdout" ]; then
    echo "[DEBUG] 포트 $try_port 는 사용 중 아님 (lsof 정상)"
  elif [ $lsof_exit_code -ne 0 ]; then
    echo "🚨 Error: lsof 명령 실패 (예외 상황)"
    exit 1
  fi
  
  # 이 포트가 사용 중이면 다음 포트로
  if [ -n "$lsof_stdout" ]; then
    continue
  fi
  
  # docker 검사
  in_use_docker=""
  docker_output=$(docker ps --format '{{.Ports}}' 2>/dev/null || true)
  if echo "$docker_output" | grep -E "[0-9\.]*:$try_port->" >/dev/null; then
    in_use_docker=1
  fi
  echo "[DEBUG] docker 결과: $in_use_docker"
  
  if [ -z "$in_use_docker" ]; then
    port=$try_port
    echo "[DEBUG] 사용 가능한 포트 발견: $port"
    if [[ "$port" =~ ^[0-9]+$ ]]; then
      zap_port=$((port + 10))
      echo "[DEBUG] ZAP 포트: $zap_port"
    else
      echo "🚨 Error: port 값이 숫자가 아님: '$port'"
      exit 1
    fi
    break
  fi
done

# 포트를 찾지 못한 경우
if [ -z "$port" ]; then
    echo "🚨 Error: 사용 가능한 포트를 찾을 수 없습니다."
    exit 1
fi

# 동적 변수 설정
containerName="${BUILD_TAG}"
zap_pidfile="zap_${zap_port}.pid"
zap_log="zap_${zap_port}.log"
zapJson="zap_test_${BUILD_TAG}.json"
timestamp=$(date +"%Y%m%d_%H%M%S")

echo "📋 설정 완료:"
echo "   - 컨테이너: $containerName"
echo "   - 웹앱 포트: $port"
echo "   - ZAP 포트: $zap_port"
echo "   - 이미지: $ECR_REPO:$DYNAMIC_IMAGE_TAG"

# ZAP 작업 디렉터리 및 플러그인 디렉터리 생성
echo "[*] ZAP 작업 디렉터리 준비 중..."
mkdir -p "$HOME/zap/zap_workdir_${zap_port}/plugin"
ZAP_BIN_DIR=$(dirname "$ZAP_BIN")

# 플러그인 복사 (에러 처리 추가)
if [ -d "${ZAP_BIN_DIR}/plugin" ]; then
    cp "${ZAP_BIN_DIR}/plugin/"*.zap "$HOME/zap/zap_workdir_${zap_port}/plugin/" 2>/dev/null || echo "⚠️ 플러그인 복사 실패 (무시하고 계속)"
else
    echo "⚠️ ZAP 플러그인 디렉터리가 없습니다: ${ZAP_BIN_DIR}/plugin"
fi

echo "[*] 웹앱 컨테이너: $containerName (포트 $port)"
echo "[*] ZAP 데몬: zap.sh (포트 $zap_port)"

# 기존 컨테이너 정리 (충돌 방지)
echo "[*] 기존 컨테이너 정리 중..."
docker rm -f "$containerName" 2>/dev/null || true

echo "[*] 웹앱 컨테이너 실행"
docker pull "$ECR_REPO:${DYNAMIC_IMAGE_TAG}"
container_id=$(docker run -d --name "$containerName" -p "${port}:8080" "$ECR_REPO:${DYNAMIC_IMAGE_TAG}")
echo "컨테이너 ID: $container_id"

# 컨테이너 시작 확인 (시간 늘림)
echo "[*] 컨테이너 시작 확인 중..."
sleep 5
for i in {1..10}; do
    if docker ps | grep "$containerName" > /dev/null; then
        echo "✅ 컨테이너 시작 성공"
        break
    fi
    echo "⏳ 컨테이너 시작 대기 중... ($i/10)"
    sleep 2
done

if ! docker ps | grep "$containerName" > /dev/null; then
    echo "❌ 컨테이너 시작 실패"
    echo "컨테이너 상태:"
    docker ps -a | grep "$containerName" || echo "컨테이너를 찾을 수 없습니다"
    echo "컨테이너 로그:"
    docker logs "$containerName" 2>/dev/null || echo "로그를 가져올 수 없습니다"
    exit 1
fi

# 웹앱 헬스체크
echo "[*] 웹앱 헬스체크 중..."
for i in {1..30}; do
    if curl -s -f "http://localhost:$port" > /dev/null 2>&1; then
        echo "✅ 웹앱 준비 완료"
        break
    fi
    echo "⏳ 웹앱 대기 중... ($i/30)"
    sleep 2
done

echo "[*] ZAP 데몬 실행 중..."
# ZAP 바이너리 존재 확인
if [ ! -f "$ZAP_BIN" ]; then
    echo "🚨 Error: ZAP 바이너리를 찾을 수 없습니다: $ZAP_BIN"
    exit 1
fi

# 기존 ZAP 프로세스 정리
if [ -f "$zap_pidfile" ]; then
    old_pid=$(cat "$zap_pidfile")
    if kill -0 "$old_pid" 2>/dev/null; then
        echo "🧹 기존 ZAP 프로세스 종료 중..."
        kill "$old_pid" 2>/dev/null || true
        sleep 3
    fi
    rm -f "$zap_pidfile"
fi

# ZAP 데몬 실행
echo "🚀 ZAP 데몬 시작..."
nohup "$ZAP_BIN" -daemon -port "$zap_port" -host 127.0.0.1 -config api.disablekey=true -dir "zap_workdir_${zap_port}" >"$zap_log" 2>&1 &
zap_pid=$!
echo $zap_pid >"$zap_pidfile"
echo "ZAP PID: $zap_pid"

# ZAP 데몬 준비 대기
echo "[*] ZAP 데몬 준비 대기 중..."
zap_ready=false
for i in {1..60}; do
    if curl -s "http://127.0.0.1:$zap_port" > /dev/null 2>&1; then
        echo "✅ ZAP 준비 완료"
        zap_ready=true
        break
    fi
    echo "⏳ ZAP 대기 중... ($i/60)"
    sleep 1
done

if [ "$zap_ready" != "true" ]; then
    echo "❌ ZAP 데몬이 준비되지 않았습니다"
    echo "ZAP 로그:"
    cat "$zap_log" 2>/dev/null || echo "ZAP 로그를 읽을 수 없습니다"
    exit 1
fi

echo "[*] 추가 대기 시간..."
sleep 40 # WebGoat 전용 헬스체크 대용

echo "[*] ZAP 스크립트 실행 ($ZAP_SCRIPT)"
if [ ! -f ~/"$ZAP_SCRIPT" ]; then
    echo "🚨 Error: ZAP 스크립트를 찾을 수 없습니다: ~/$ZAP_SCRIPT"
    exit 1
fi

chmod +x ~/"$ZAP_SCRIPT"
echo "🔍 ZAP 스캔 시작..."
~/"$ZAP_SCRIPT" "$containerName" "$zap_port" "$startpage" "$port"

# 결과 파일 확인
if [ ! -f ~/zap_test.json ]; then
    echo "❌ ZAP 결과 파일이 존재하지 않습니다."
    echo "홈 디렉터리 내용:"
    ls -la ~/zap* 2>/dev/null || echo "zap 관련 파일이 없습니다"
    exit 1
fi

echo "[*] 결과 파일 저장"
cp ~/zap_test.json "$zapJson"
cp "$zapJson" zap_test.json
echo "✅ 결과 파일 저장 완료: $zapJson"

echo "[*] 정리 중..."
# 웹앱 컨테이너 제거
if docker ps -a | grep "$containerName" > /dev/null; then
    docker rm -f "$containerName" 2>/dev/null && echo "🧹 웹앱 컨테이너 제거 완료" || echo "⚠️ 웹앱 컨테이너 제거 실패"
fi

# ZAP 데몬 종료
if [ -f "$zap_pidfile" ]; then
    zap_pid=$(cat "$zap_pidfile")
    if kill -0 "$zap_pid" 2>/dev/null; then
        kill "$zap_pid" && echo "🧹 ZAP 데몬 종료 완료" || echo "⚠️ ZAP 데몬 종료 실패"
        sleep 2
    fi
    rm -f "$zap_pidfile"
fi

# ZAP 작업 디렉터리 제거 (선택사항)
if [ -d "$HOME/zap/zap_workdir_${zap_port}" ]; then
    echo "ℹ️  ZAP 작업 디렉터리 유지 (로그 보존): $HOME/zap/zap_workdir_${zap_port}"
    # 원한다면 아래 주석 해제
    # rm -rf "$HOME/zap/zap_workdir_${zap_port}" && echo "🧹 ZAP 작업 디렉터리 제거 완료" || echo "⚠️ ZAP 작업 디렉터리 제거 실패"
fi

echo "🎉 스크립트 완료: $(date)"
echo "📊 결과 파일: $(pwd)/$zapJson"
