# Statica

Statica is a code quality and security scanning tool (for macOS and Linux). Statica can show output on CLI or generate an HTML report.

Statica is intended for situations where you can't compile the code, like:

* if you're looking at .NET Framework apps and you have a Mac
* if there are binary dependencies you can't access
* if the code doesn't compile

## Prerequisites

Ensure the following tools are installed and available in your `PATH`:

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
./statica <path to app source> [html]
```
* <path to app source>: The directory containing the source code to be scanned.
* [html]: Optional argument. If provided, an HTML report will be generated.

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