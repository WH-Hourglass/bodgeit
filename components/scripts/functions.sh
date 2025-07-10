#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

detect_java_version() {
    local REPO_NAME="$1"
    local BUILD_ID="$2"

    echo "[+] 언어 및 Java 버전 탐지 시작"
    cd "/tmp/${REPO_NAME}" || exit 1

    IMAGE_TAG="cli"
    JAVA_VERSION=""
    BUILD_FILE=""

    if [[ -f "pom.xml" ]]; then
        echo "[🔍] pom.xml 감지됨 – Java Maven 프로젝트"
        BUILD_FILE="pom.xml"
    elif [[ -f "build.gradle.kts" ]]; then
        echo "[🔍] build.gradle.kts 감지됨 – Java Gradle(Kotlin DSL) 프로젝트"
        BUILD_FILE="build.gradle.kts"
    elif [[ -f "build.gradle" ]]; then
        echo "[🔍] build.gradle 감지됨 – Java Gradle 프로젝트"
        BUILD_FILE="build.gradle"
    fi

    if [[ -n "$BUILD_FILE" ]]; then
        JAVA_VERSION=$(python3 "$SCRIPT_DIR/pom_to_docker_image.py" "$BUILD_FILE" 2>/dev/null | tr -d '\r')
        if [[ -z "$JAVA_VERSION" ]]; then
            echo "[⚠️] Bedrock 기반 감지 실패 – 기본 java 사용"
            IMAGE_TAG="java"
        else
            echo "[✅] 감지된 Java 버전: $JAVA_VERSION"
            IMAGE_TAG=$(python3 "$SCRIPT_DIR/docker_tag.py" "$JAVA_VERSION" 2>/dev/null | tr -d '\r')
            [[ -z "$IMAGE_TAG" ]] && IMAGE_TAG="java"
        fi
    elif [[ -f "package.json" || -f "requirements.txt" || -f "pyproject.toml" || -f "go.mod" || -f "Cargo.toml" ]]; then
        echo "[ℹ️] Java 외 언어 프로젝트 감지됨 – CLI 이미지 사용"
        IMAGE_TAG="cli"
        JAVA_VERSION="Not_Java"
    else
        echo "[⚠️] 지원되는 빌드 파일을 감지하지 못함 – 기본(cli) 사용"
        IMAGE_TAG="cli"
        JAVA_VERSION="UNKNOWN"
    fi

    echo "[ℹ️] 최종 선택된 Docker 이미지 태그: $IMAGE_TAG"
    echo "$IMAGE_TAG" > "/tmp/cdxgen_image_tag_${REPO_NAME}_${BUILD_ID}.txt"
    echo "$JAVA_VERSION" > "/tmp/cdxgen_java_version_${REPO_NAME}_${BUILD_ID}.txt"
}

upload_sbom() {
    local REPO_NAME="$1"
    local BUILD_ID="$2"

    if [[ -z "$REPO_NAME" || -z "$BUILD_ID" ]]; then
        echo "❌ upload_sbom 함수 호출 시 REPO_NAME과 BUILD_ID가 필요합니다."
        return 1
    fi

    source /home/ec2-user/.env

    local SBOM_FILE="/tmp/${REPO_NAME}/sbom_${REPO_NAME}_${BUILD_ID}.json"

    if [[ ! -f "$SBOM_FILE" ]]; then
        echo "❌ SBOM 파일이 존재하지 않습니다: $SBOM_FILE"
        return 1
    fi

    local PROJECT_VERSION="${BUILD_ID}_$(date +%Y%m%d_%H%M%S)"
    echo "🚀 SBOM 업로드 시작: $SBOM_FILE (projectVersion: $PROJECT_VERSION)"

    curl -X POST http://localhost:8080/api/v1/bom \
        -H "X-Api-Key: $DT_API_KEY" \
        -F "projectName=$REPO_NAME" \
        -F "projectVersion=$PROJECT_VERSION" \
        -F "bom=@$SBOM_FILE" \
        -F "autoCreate=true"
}
