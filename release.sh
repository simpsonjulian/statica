#!/bin/bash
version=$1

if [ -z "$version" ]; then
    echo "Usage: $0 <version>"
    echo "Previous versions:"
    gh release list
    exit 1
fi

set -euo pipefail

# Releasing from a feature branch pushes the bump there while `gh release
# create` still tags the default branch, leaving the tag without the bump
branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != "main" ]; then
    echo "Refusing to release from '${branch}'; switch to main first." >&2
    exit 1
fi

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "Working tree has uncommitted changes; commit or stash first." >&2
    exit 1
fi

# Update version in gemspec
new_version_line="spec.version       = \"$version\""
sed -i '' "s/spec.version.*=.*/${new_version_line}/" statica.gemspec

# Gemfile.lock pins the gemspec version, so a stale lock fails the frozen
# `bundle install --deployment` that CI runs
bundle install

# Build to validate the gemspec, but keep the artifact out of the repo
gem build statica.gemspec
rm -f statica-"$version".gem

git add statica.gemspec Gemfile.lock
git commit -m "Bump version to ${version}"
git push

# Create GitHub release and update Homebrew. --target pins the tag to the
# commit just pushed rather than whatever the default branch happens to be.
brew update
gh release create v"$version" --target "$(git rev-parse HEAD)" --generate-notes
brew bump-formula-pr --version "$version" --no-fork simpsonjulian/statica-tap/statica
