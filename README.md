# Statica SAST Tool

Statica is Static Application Security Testing (SAST) tool for macOS and Linux.

Statica is designed to be used in situations where you can't compile the code, like:

* you're looking at .NET Framework apps, and you don't have a Windows computer
* there are binary dependencies you can't access
* the code doesn't compile

Statica will run other tools in the Homebrew ecosystem, and present a single report in console output or HTML.

## Installing

Statica is builds upon the Homebrew ecosystem. If you have homebrew working on your computer, just run:

```bash
  brew install simpsonjulian/statica-tap/statica
```

If you want to run Statica locally, then you'll need to install the following tools:

```bash
brew install semgrep \
    dependency-check \
    trivy \
    sarif \
    lizard-analyzer \
    checkov \
    pmd
```

You'll also want Ruby 3.0.0 or later installed to do the HTML.

## Usage

```bash
statica <path to app source> [html|console]
```
* <path to app source>: The directory containing the source code to be scanned.
* [html]: Optional argument. If provided, an HTML report will be generated.
* [console]: Optional argument. If provided, the report will be displayed in the console.

# License
This project is licensed under the MIT License.

# TODO

* add the tool name to the findings in the HTML report
* report stats from the run

# Future tools

I'm thinking of adding:

* shellcheck
* action-lint
* snyk
* codeql
