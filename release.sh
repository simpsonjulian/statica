#!/bin/bash
version=$1

if [ -z "$version" ]; then
    echo "Usage: $0 <version>"
    echo "Previous versions:"
    gh release list
    exit 1
fi

set -euo pipefail

# Update version in gemspec
new_version_line="spec.version       = \"$version\""
sed -i '' "s/spec.version.*=.*/${new_version_line}/" statica.gemspec

# Build and commit the gem
gem build statica.gemspec
git add statica.gemspec statica-"$version".gem
git commit -m "Bump version to ${version}"
git push

# Create GitHub release and update Homebrew
brew update
gh release create v"$version" --generate-notes
brew bump-formula-pr --version "$version" statica
