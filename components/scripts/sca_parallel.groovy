def runScaJobs() {
    def repoName = 'WebGoat'
    def repoUrl = "https://github.com/WH-Hourglass/${repoName}.git"

    echo "📌 커밋 수 계산 중"
    def commitCount = sh(
        script: "git rev-list --count HEAD ^HEAD~10",
        returnStdout: true
    ).trim().toInteger()

    def parallelCount = Math.min(commitCount, 2) // 병렬 최대 2개
    def jobs = [:]

    for (int i = 1; i <= parallelCount; i++) {
        def index = i
        def agent = "SCA-agent${(index % 2) + 1}"
        def buildTag = "${env.BUILD_ID}-${index}"  // ✅ 변수로 미리 만들어야 에러 안 남

        jobs["SCA-${repoName}-${index}"] = {
            node(agent) {
                stage("SCA ${repoName}-${index}") {
                    echo "▶️ 병렬 SCA 실행 – 대상: ${repoName}, 인덱스: ${index}, Agent: ${agent}"

                    // 소스코드 체크아웃 (보장)
                    checkout scm

                    // run_sbom_pipeline.sh 파일 찾기 및 실행
                    sh """
                        echo '[*] 현재 디렉토리: \$(pwd)'
                        echo '[*] 파일 목록:' && ls -al

                        SCRIPT_PATH="./components/scripts/run_sbom_pipeline.sh"

                        if [ ! -f "\$SCRIPT_PATH" ]; then
                          echo '⚠️ 예상 위치에 스크립트 없음. find로 탐색 시도...'
                          SCRIPT_PATH=\$(find . -name 'run_sbom_pipeline.sh' -print -quit)
                        fi

                        if [ -z "\$SCRIPT_PATH" ]; then
                          echo '❌ run_sbom_pipeline.sh 파일을 찾을 수 없습니다.'
                          exit 1
                        fi

                        echo "✅ 실행할 스크립트: \$SCRIPT_PATH"
                        chmod +x "\$SCRIPT_PATH"
                        "\$SCRIPT_PATH" '${repoUrl}' '${repoName}' '${buildTag}'
                    """
                }
            }
        }
    }

    parallel jobs
}

return this
