#!/bin/bash
source components/dot.env
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO