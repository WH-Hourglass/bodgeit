#!/bin/bash
source components/dot.env
zip -r $BUNDLE appspec.yaml Dockerfile taskdef.json