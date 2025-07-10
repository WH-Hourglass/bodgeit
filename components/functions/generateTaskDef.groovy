def call(env) {
    def json = """{
  "family": "webgoat-task-def",
  "networkMode": "awsvpc",
  "containerDefinitions": [
    {
      "name": "webgoat",
      "image": "${env.ECR_REPO}:${env.IMAGE_TAG}",
      "memory": 512,
      "cpu": 256,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ]
    }
  ],
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::535052053335:role/ecsTaskExecutionRole"
}"""
    writeFile file: 'taskdef.json', text: json
}

return this
