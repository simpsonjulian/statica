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

## Features

### Graph-based Analysis

Statica uses graph analysis (via the RGL library) to identify patterns in findings:

- **Interactive Graph Visualization**: The HTML report starts with an interactive graph (powered by vis.js) showing:
  - Relationships between analysis tools, findings, and files
  - Densely connected files (files with 3+ findings)
  - Color-coded nodes by severity (red for errors, orange for warnings, blue for notes)
  - Hierarchical layout showing the flow: Analysis Tool → Finding → File
  - Fully interactive: drag individual nodes to reorganize, scroll to zoom, pan the view

- **Hotspot Files**: Table showing files with multiple findings, helping you identify the most problematic files that need attention first.

- **Widespread Findings**: Identifies which security/quality issues appear most frequently across multiple files, helping you prioritize systemic problems.

The graph structure follows: `(analysis)-[:HAS]->(finding)-[:IN]->(file)`

### Reports

- **Console Output**: Summary of findings grouped by severity
- **HTML Report**: Comprehensive report including:
  - Repository metadata (URL, branch, commit SHA)
  - Interactive graph visualization at the top
  - Hotspot files table (files with multiple findings)
  - Detailed findings grouped by severity and rule
  - Widespread findings table (issues affecting multiple files)

# License
This project is licensed under the MIT License.

# Future tools

* shellcheck
* action-lint
* snyk
* codeql
