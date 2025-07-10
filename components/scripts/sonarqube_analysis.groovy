// SonarQube 분석 시작
def scannerHome = tool 'MySonarScanner'
def mvnHome = tool 'Maven3'

sh """
${mvnHome}/bin/mvn compile dependency:copy-dependencies -DoutputDirectory=target/dependency -DskipTests
"""


withSonarQubeEnv(env.SONARQUBE_ENV) {
    sh """
    export NODE_OPTIONS=--max_old_space_size=4096
    ${scannerHome}/bin/sonar-scanner \
        -Dsonar.projectKey=webgoat \
        -Dsonar.sources=. \
        -Dsonar.java.binaries=target/classes \
        -Dsonar.java.libraries=target/dependency/*.jar \
        -Dsonar.python.version=3.9
    """
}

// SonarQube API 결과 수집 및 파일 저장
withSonarQubeEnv(env.SONARQUBE_ENV) {
    script {
        def timestamp = sh(script: "date +%F_%H-%M-%S", returnStdout: true).trim()
        env.REPORT_FILE = "sonar_issues_${timestamp}.json"

        sh """
        curl -s -H "Authorization: Bearer $SONAR_AUTH_TOKEN" \\
          "$SONAR_HOST_URL/api/issues/search?componentKeys=webgoat" \\
          -o ${env.REPORT_FILE}
        """
    }
}

// S3로 업로드
sh """
aws s3 cp ${env.REPORT_FILE} s3://ss-bucket-0305/sonarqube-reports/${env.REPORT_FILE} --region ap-northeast-2
"""