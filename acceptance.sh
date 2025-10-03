#!/bin/bash


gh repo clone WebGoat/WebGoat -- --depth 1

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

set -euo pipefail

brew install semgrep \
    jq \
    retire \
    trivy \
    lizard-analyzer \
    checkov \
    pmd \
    bearer/tap/bearer

pipx install sarif-tools semgrep-rules-manager

./statica WebGoat html
