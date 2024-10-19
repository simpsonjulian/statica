#!/bin/bash



eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

set -euo pipefail

brew install simpsonjulian/statica-tap/statica bearer/tap/bearer

pipx install sarif-tools
npm install -g jscpd-sarif-reporter

cd /tmp

gh repo clone WebGoat/WebGoat
statica WebGoat html
