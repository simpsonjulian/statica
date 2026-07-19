#!/bin/bash


gh repo clone WebGoat/WebGoat -- --depth 1

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

set -euo pipefail

# Homebrew's Linux build sandbox (bwrap) breaks staging of from-source tap
# formulae (Errno::EINVAL @ apply2files) on GitHub runners
export HOMEBREW_NO_SANDBOX_LINUX=1

brew install semgrep \
    jq \
    retire \
    trivy \
    lizard-analyzer \
    checkov \
    pmd \
    coreutils \
    bearer/tap/bearer

pipx install sarif-tools semgrep-rules-manager
bundle config set without 'development'
bundle install
bundle exec ./statica WebGoat html
