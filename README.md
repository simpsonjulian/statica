# Statica

Statica is a tool (for macOS and Linux) that scans a given source directory for quality and security issues. It can also generate an HTML summary of the reports.

Statica is intended for situations where you can't compile the code, like:

* if you're looking at .NET Framework apps and you have a Mac
* if there are binary dependencies you can't access
* if the code doesn't compile


## Prerequisites

Ensure the following tools are installed and available in your `PATH`:

```bash
brew install semgrep dependency-check trivy sarif lizard-analyzer \
     checkov
```

## Usage

```bash
./statica <path to app source> [html]
```
* <path to app source>: The directory containing the source code to be scanned.
* [html]: Optional argument. If provided, an HTML report will be generated.

# License
This project is licensed under the MIT License.