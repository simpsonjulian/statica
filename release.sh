#!/bin/bash
version=$1

if [ -z "$version" ]; then
    echo "Usage: $0 <version>"
    echo "Previous versions:"
    gh release list
    exit 1
fi

set -euo pipefail
brew update
gh release create v"$version" --generate-notes
brew bump-formula-pr --version "$version" statica