#!/bin/bash

gh repo clone WebGoat/WebGoat

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

set -euo pipefail

brew install semgrep \
    dependency-check \
    trivy \
    lizard-analyzer \
    checkov \
    pmd \
    bearer/tap/bearer

pip install sarif-tools

./statica WebGoat html
