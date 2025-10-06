# Statica SAST Tool

Statica is a Static Application Security Testing (SAST) tool for macOS and Linux.

Statica is designed to be used in situations where you can't compile the code, like:

* you're looking at .NET Framework apps, and you don't have a Windows computer
* there are binary dependencies you can't access
* the code doesn't compile

Statica will run other tools in the Homebrew ecosystem, and present a single report in console output or HTML.

## Installing

Statica builds upon the Homebrew ecosystem. If you have homebrew working on your computer, just run:

```bash
  brew install simpsonjulian/statica-tap/statica
```

If you want to run Statica locally, then you'll need to install the following tools:

```bash
brew install semgrep \
    jq \
    retire \
    trivy \
    sarif \
    lizard-analyzer \
    checkov \
    pmd
pip install semgrep-rules-manager
```

You'll also want Ruby 3.0.0 or later installed to do the HTML.

## Usage

```bash
statica <path to app source> [html|console]
```
- *path to app source* - the directory containing the source code to be scanned.
- *html* - if provided, an HTML report will be generated.
- *console* - if provided, the report will be displayed in the console.

# License
This project is licensed under the MIT License.

# TODO
* report stats from the run for aggregation
* report on the most problematic files

# Future tools

* shellcheck
* action-lint
* snyk
* codeql
