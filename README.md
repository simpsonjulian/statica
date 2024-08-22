# Statica

Statica is a tool that scans a given source directory using various tools and generates reports in SARIF format. It can also generate an HTML summary of the reports.

## Prerequisites

Ensure the following tools are installed and available in your `PATH`:
- `semgrep`
- `dependency-check`
- `trivy`
- `sarif`

## Usage

```bash
./statica <path to app source> [html]
```
* <path to app source>: The directory containing the source code to be scanned.
* [html]: Optional argument. If provided, an HTML report will be generated.

# License
This project is licensed under the MIT License.