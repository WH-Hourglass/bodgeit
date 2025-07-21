#!/bin/bash
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO
