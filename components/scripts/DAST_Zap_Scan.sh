#!/bin/bash
source components/dot.env

# 기본값
CONTAINER_NAME="${BUILD_TAG}"
IMAGE_TAG="${DYNAMIC_IMAGE_TAG}"
ZAP_SCRIPT="${ZAP_SCRIPT:-zap_scan.sh}"
ZAP_BIN="${ZAP_BIN:-$HOME/zap/zap.sh}" # zap.sh 실행 경로
startpage="${1:-}"

echo "DEBUG: 변수 설정 완료"

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



# 동적 변수 설정
containerName="${BUILD_TAG}"
zap_pidfile="zap_${zap_port}.pid"
zap_log="zap_${zap_port}.log"
zapJson="zap_test_${BUILD_TAG}.json"
timestamp=$(date +"%Y%m%d_%H%M%S")



# ZAP 작업 디렉터리 및 플러그인 디렉터리 생성 및 애드온 복사 (zap 데몬 병렬 실행할 때 에드온으로 인한 에러 방지용)
mkdir -p "$HOME/zap/zap_workdir_${zap_port}/plugin"
ZAP_BIN_DIR=$(dirname "$ZAP_BIN")
cp "${ZAP_BIN_DIR}/plugin/"*.zap "$HOME/zap/zap_workdir_${zap_port}/plugin/"

echo "[*] 웹앱 컨테이너: $containerName (포트 $port)"
echo "[*] ZAP 데몬: zap.sh (포트 $zap_port)"


echo "[*] 웹앱 컨테이너 실행"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REPO"
docker pull "$ECR_REPO:${DYNAMIC_IMAGE_TAG}"
docker run -d --name "$containerName" -p "${port}:8080" "$ECR_REPO:${DYNAMIC_IMAGE_TAG}"



echo "[*] ZAP 데몬 실행 중..."
# 데몬을 -dir 명령어로 실행해서 병렬 실행 가능하도록 하는 것임 zap_workdir_${zap_port}는 zap 데몬용 디렉터리
nohup "$ZAP_BIN" -daemon -port "$zap_port" -host 127.0.0.1 -config api.disablekey=true -dir "zap_workdir_${zap_port}" >"$zap_log" 2>&1 &
echo $! >"$zap_pidfile"
for i in {1..60}; do # 데몬 실행 체크도 그냥 여기서 하도록 코드 옮김
  curl -s "http://127.0.0.1:$zap_port" > /dev/null && { echo "[+] ZAP 준비 완료"; break; }
  sleep 1
done 
sleep 40 #WebGoat 전용 헬스체크 대용 (헬스체크를 구현 안해서 추가한거라 나중에는 없애야 함)

echo "[*] ZAP 스크립트 실행 ($ZAP_SCRIPT)"
chmod +x ~/"$ZAP_SCRIPT"
~/"$ZAP_SCRIPT" "$containerName" "$zap_port" "$startpage" "$port" # $port인자 추가

if [ ! -f ~/zap_test.json ]; then
  echo "❌ ZAP 결과 파일이 존재하지 않습니다."
  exit 1
fi

echo "[*] 결과 파일 저장"
cp ~/zap_test.json "$zapJson"
cp "$zapJson" zap_test.json

echo "[*] 정리 중..."
docker rm -f "$containerName" 2>/dev/null && echo "🧹 웹앱 컨테이너 제거 완료" || echo "⚠️ 웹앱 컨테이너 제거 실패"

if [ -f "$zap_pidfile" ]; then
  kill "$(cat "$zap_pidfile")" && echo "🧹 ZAP 데몬 종료 완료" || echo "⚠️ ZAP 데몬 종료 실패"
  rm -f "$zap_pidfile"
  sleep 2
fi

# 위에서 만든 zap 데몬 병렬처리용 전용 db 삭제하는 명령어들인데 
# 지금 코드에서는 zap_workdir_${zap_port}로 만들어져서 폴더 갯수 관리하려고 제거하는 코드를 추가한건데
# cicd에 적용할때는 zap_workdir_${빌드번호} 형식으로 수정하고 폴더 지우는 코드는 제거하는게 좋을듯
# 해당 폴더에 zap 데몬 로그가 남아서 안지우는게 좋을듯
if [ -d "$HOME/zap/zap_workdir_${zap_port}" ]; then
  rm -rf "$HOME/zap/zap_workdir_${zap_port}" && echo "🧹 ZAP 작업 디렉터리 제거 완료" || echo "⚠️ ZAP 작업 디렉터리 제거 실패"
fi
