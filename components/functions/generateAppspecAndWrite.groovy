def call(region) {
    def taskDefArn = sh(
        script: "aws ecs register-task-definition --cli-input-json file://taskdef.json --query 'taskDefinition.taskDefinitionArn' --region ap-northeast-2 --output text",
        returnStdout: true
    ).trim()

    def appspec = """version: 0.0
Resources:
  - TargetService:
      Type: AWS::ECS::Service
      Properties:
        TaskDefinition: ${taskDefArn}
        LoadBalancerInfo:
          ContainerName: "webgoat"
          ContainerPort: 8080
"""

    writeFile file: 'appspec.yaml', text: appspec
}

return this