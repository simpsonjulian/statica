#!/bin/bash



eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

set -euo pipefail

brew install simpsonjulian/statica-tap/statica bearer/tap/bearer

TEMP=$(mktemp -d)
( cd "${TEMP}" && gh repo clone WebGoat/WebGoat -- --depth 1  &&  statica WebGoat html )

rm -r "${TEMP}"
