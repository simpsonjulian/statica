#!/bin/bash
version=$1

set -euo pipefail
brew update
gh release create v$version --generate-notes
brew bump-formula-pr --version $version statica -n

## brew tap simpsonjulian/
# brew audit --new --tap simpsonjulian/core --formula statica -v

# ensure correct tap is done
# brew bump-formula-pr will work fine
