#!/bin/bash


gh repo clone WebGoat/WebGoat -- --depth 1

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

set -euo pipefail

# Homebrew's Linux build sandbox (bwrap) breaks staging of from-source tap
# formulae (Errno::EINVAL @ apply2files) on GitHub runners
export HOMEBREW_NO_SANDBOX_LINUX=1

# The runner image pins an old Homebrew and disables auto-update, which cannot
# parse current homebrew-core formulae ("unknown install step: ...")
brew update

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
