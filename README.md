# Statica SAST Tool

Statica is a Static Application Security Testing (SAST) tool for macOS and Linux.

Statica is designed to be used in situations where you can't compile the code, like:

* you're looking at .NET Framework apps, and you don't have a Windows computer
* there are binary dependencies you can't access
* the code doesn't compile

Statica will run other tools in the Homebrew ecosystem, and present a single report in console output or HTML.

## Installing

### Homebrew

Statica builds upon the Homebrew ecosystem. If you have homebrew working on your computer, just run:

```bash
  brew install simpsonjulian/statica-tap/statica
```

### Docker

You can also run Statica using Docker:

```bash
# Build the image
make docker-build

# Run statica on a local directory
docker run --rm -v /path/to/code:/code statica:latest statica /code html

# Example: scan the current directory
docker run --rm -v $(pwd):/code statica:latest statica /code console
```

### Local Installation

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

### Branching topology

The `topology` analyser reports on the health of the branching workflow rather than the code:
branches that never merge back, changes stranded on a release line, and merges that were
expensive because the branches were allowed to drift.

It has no opinion on gitflow versus trunk-based development. It reports facts about the commit
graph and leaves the judgement to you.

It is strictly read-only — everything is computed from `for-each-ref`, `rev-list`, `merge-base`,
`diff` and `patch-id`. It never checks out, merges, fetches, or touches the index, so it is safe
to run against a repository you are working in.

#### Requirements

The analyser needs real history. It requires no tools beyond `git`, but:

- **Source with no `.git` at all** — the common case when code arrives as an archive — is not an
  error. The analyser contributes nothing and says nothing.
- **Shallow and partial clones are skipped**, with a single diagnostic on stderr. A shallow clone
  has no merge bases, so every branch would look unmerged and every finding would be wrong. It is
  better to report nothing than to report confidently wrong things.
- **In CI this matters**, because `actions/checkout` defaults to `fetch-depth: 1`. The analyser
  will skip every check unless you ask for the full history:

  ```yaml
  - uses: actions/checkout@v5
    with:
      fetch-depth: 0
  ```

Walks are bounded: 12 months of history, at most 1000 merges and 500 branches, and the whole
analyser abandons its remaining work after 120 seconds. On a partial run it says so on stderr.

#### What it checks

Integration branches are whichever of `main`, `master` and `develop` exist; release lines are
`release/*` and `hotfix/*`. Branches under `spike/`, `archive/`, `experiment/`, `tmp/`, `wip/`,
`poc/`, `dependabot/` and `renovate/` are treated as intentional dead ends and never reported as
unmerged.

##### branch-never-merged

A branch that stopped moving but never landed is either abandoned work nobody deleted, or a change
someone believes shipped and did not.

Severity scales with how long the branch has been sitting rather than the mere fact it exists —
nothing under 30 days, `note` from 30, `warning` from 90, `error` from 180. A feature branch a few
days old is work in progress, not a finding.

Detection is layered, because ancestry alone reports every squash-merged branch as unmerged and
squash merges are the default on most forges:

1. `merge-base --is-ancestor`, which catches true merges and fast-forwards.
2. `git cherry`, which catches rebase merges and cherry-picks, where per-commit patch IDs survive.
3. The branch's cumulative diff patch ID against mainline's commits, which catches squash merges.

Step 3 is not redundant. A squash collapses N commits into one whose patch ID matches none of the
originals, so `git cherry` alone reports squash-merged branches as unmerged.

##### release-commit-not-forward-ported

A fix applied to a release line and never forward-ported disappears at the next release, and
typically resurfaces as a reopened bug. One finding per release branch, naming the commits.

Uses `rev-list --cherry-pick`, so commits that reached mainline by cherry-pick rather than merge
are not reported.

##### merge-high-divergence

Branches that developed in parallel for more than 8 weeks, with at least 5 commits on each side,
before merging. Both sides have to have genuinely moved — otherwise this fires on a branch that
simply sat still while mainline advanced, which is `branch-never-merged`'s problem.

The merge is where the pain surfaced; the cost was incurred over the preceding weeks.

##### merge-high-overlap

Files modified on *both* sides of the merge base — the files the merge had to reconcile by hand.
Reported when at least 10 files overlap and they are at least 25% of the smaller side.

These findings carry real file paths, so they flow into the hotspot table and the graph. A file
that repeatedly appears in high-overlap merges *and* carries findings from other tools is a
genuinely useful signal, and that clustering is most of the reason to do this inside Statica.

##### merge-large

Merges integrating at least 100 files or 10,000 changed lines in one step. Informational: the size
is not a defect, but it bounds how much confidence any review of it could have had.

##### repeated-back-merge

Mainline merged into a branch three or more times before the branch landed. Repeatedly pulling
mainline in is how a long-lived branch stays merge-able, and a reliable symptom of a branch that
lived longer than the work justified.

##### criss-cross-merge

Two branches merged into each other in both directions, leaving more than one merge base. Later
merges between them pick a base ambiguously, and the one git picks may not be the one you would.

##### topology-metrics

One `note` carrying merge-commit ratio, live branch count, mean and p90 branch lifetime, and the
maximum number of branches in flight at once.

These are context for a human, not defects, and they never fail a build. They are deliberately not
combined into a composite score — that would be arbitrary, and people would argue with the number
instead of looking at the inputs.

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
