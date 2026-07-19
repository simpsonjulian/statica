#!/bin/bash



eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

set -euo pipefail

# Homebrew's Linux build sandbox (bwrap) breaks staging of from-source tap
# formulae (Errno::EINVAL @ apply2files) on GitHub runners
export HOMEBREW_NO_SANDBOX_LINUX=1

brew install simpsonjulian/statica-tap/statica bearer/tap/bearer

TEMP=$(mktemp -d)
( cd "${TEMP}" && gh repo clone WebGoat/WebGoat -- --depth 1  &&  statica WebGoat html )

rm -r "${TEMP}"
