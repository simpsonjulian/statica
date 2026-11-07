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
    scc \
    checkov \
    pmd \
    coreutils \
    ripgrep \
    exiftool \
    bearer/tap/bearer

pipx install sarif-tools semgrep-rules-manager
# Skip development gems for this run only. `bundle config set` would write this into the
# checkout's .bundle/config, where it outlives the run and breaks `make test` afterwards.
export BUNDLE_WITHOUT=development
bundle install
bundle exec ./statica WebGoat html
