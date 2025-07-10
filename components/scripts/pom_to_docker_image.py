import boto3
import json
import sys
import os

region = "ap-northeast-2"
model_id = "arn:aws:bedrock:ap-northeast-2:535052053335:inference-profile/apac.anthropic.claude-3-7-sonnet-20250219-v1:0"
bedrock = boto3.client("bedrock-runtime", region_name=region)

if len(sys.argv) < 2:
    print("UNKNOWN")
    sys.exit(0)

file_path = sys.argv[1]

if not os.path.isfile(file_path):
    print("UNKNOWN")
    sys.exit(0)

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

trimmed_content = content[:7000]

# 프롬프트 설정
if file_path.endswith("pom.xml"):
    prompt = "아래 pom.xml에서 java version만 한 줄로 뽑아서 출력해줘. 설명 없이 버전 문자열만!"
elif file_path.endswith("build.gradle") or file_path.endswith("build.gradle.kts"):
    prompt = "아래 build.gradle 또는 build.gradle.kts 파일에서 java version만 한 줄로 뽑아서 출력해줘. 설명 없이 버전 문자열만!"
else:
    print("UNKNOWN")
    sys.exit(0)

# LLM 호출
body = json.dumps({
    "anthropic_version": "bedrock-2023-05-31",
    "messages": [
        {"role": "user", "content": prompt},
        {"role": "user", "content": trimmed_content}
    ],
    "max_tokens": 50,
    "temperature": 0.0,
    "top_p": 1.0
})

response = bedrock.invoke_model(
    modelId=model_id,
    contentType="application/json",
    accept="application/json",
    body=body
)

response_body = json.loads(response['body'].read())
content_items = response_body.get("content", [])

if isinstance(content_items, list) and len(content_items) > 0:
    result = content_items[0].get("text", "").strip()
else:
    result = "UNKNOWN"

print(result)
