# frozen_string_literal: true

require 'open3'
require 'sarif'
require 'set'

# Reports on the health of a repository's branching workflow: branches that
# never merge back, changes stranded on a release line, and merges that were
# expensive because the branches were allowed to drift.
#
# Strictly read-only. Everything is computed from for-each-ref, rev-list,
# merge-base, diff and patch-id; nothing here checks out, merges, fetches, or
# touches the index, so it is safe against a bare or dirty repository that
# someone else is working in.
class TopologyAnalyzer
  TOOL_NAME = 'topology'
  # Anchors into the README's rule reference, one heading per rule id.
  HELP_BASE = 'https://github.com/simpsonjulian/statica#'

  # Bounded runtime. Every check fans out over refs or merges, and Statica gets
  # pointed at large repositories, so each walk is capped and the whole run is
  # abandoned once the deadline passes.
  WINDOW_MONTHS = 12
  MAX_MERGES = 1000
  MAX_PATCH_ID_COMMITS = 2000
  MAX_BRANCHES = 500
  DEADLINE_SECONDS = 120

  INTEGRATION_CANDIDATES = %w[main master develop].freeze
  RELEASE_PATTERNS = [%r{\Arelease/}, %r{\Ahotfix/}].freeze

  # Branches that are conventionally dead ends. Reporting them as unmerged is
  # noise: not coming back is the whole point of a spike. The bot prefixes are
  # here because a lingering dependabot branch means a superseded or closed
  # pull request, which says nothing about the branching model - and on a repo
  # with dependabot enabled they otherwise drown out the real findings.
  EXCLUDED_PATTERNS = [
    %r{\Aspikes?/}, %r{\Aarchived?/}, %r{\Aexperiments?/},
    %r{\Atmp/}, %r{\Awip/}, %r{\Apocs?/},
    %r{\Adependabot/}, %r{\Arenovate/}
  ].freeze

  # A branch is only worth mentioning once it has been abandoned for a while.
  # A feature branch a few days old is just work in progress, so severity keys
  # off how long it has been sitting rather than the mere fact of existing.
  STALE_AFTER_DAYS = 30
  BRANCH_LEVELS = [[180, 'error'], [90, 'warning'], [STALE_AFTER_DAYS, 'note']].freeze

  # Divergence needs both sides to have genuinely moved, otherwise it fires on
  # a branch that simply sat still while mainline advanced - which is check 1's
  # problem, not this one's.
  DIVERGENCE_DAYS = 56
  DIVERGENCE_DAYS_HIGH = 112
  DIVERGENCE_MIN_COMMITS = 5

  OVERLAP_MIN_FILES = 10
  OVERLAP_MIN_RATIO = 0.25
  OVERLAP_HIGH_FILES = 30
  # Overlap findings carry real paths so they reach the hotspot table, but a
  # merge touching 400 shared files should not emit 400 results.
  OVERLAP_MAX_LOCATIONS = 10

  BIG_MERGE_FILES = 100
  BIG_MERGE_LINES = 10_000

  BACK_MERGE_THRESHOLD = 3

  RULES = {
    'branch-never-merged' => {
      level: 'warning',
      text: 'Branch has never been merged into an integration branch',
      help: 'A branch that stopped moving but never landed is either abandoned work nobody ' \
            'deleted, or a change someone believes shipped and did not. Both are worth ' \
            'resolving: delete it, or merge it. Squash- and rebase-merged branches are ' \
            'detected by patch ID and are not reported.'
    },
    'release-commit-not-forward-ported' => {
      level: 'warning',
      text: 'Commits exist on a release branch but not on mainline',
      help: 'A fix applied to a release line and never forward-ported disappears at the next ' \
            'release, and typically resurfaces as a reopened bug. Commits that were ' \
            'cherry-picked to mainline are detected by patch ID and are not reported.'
    },
    'merge-high-divergence' => {
      level: 'warning',
      text: 'Branches developed in parallel for a long time before merging',
      help: 'The merge is where the pain surfaced, but the cause is how long the two sides ' \
            'were allowed to drift. Long-lived parallel development makes every merge more ' \
            'expensive and every conflict resolution more likely to be wrong.'
    },
    'merge-high-overlap' => {
      level: 'warning',
      text: 'Merge had to reconcile many files changed on both sides',
      help: 'Files modified on both sides of the merge base are the files the merge had to ' \
            'reconcile by hand. Sustained high overlap means two streams of work are ' \
            'competing for the same code and the branching model is not keeping them apart.'
    },
    'merge-large' => {
      level: 'note',
      text: 'Merge integrated a large amount of change at once',
      help: 'Big-bang integrations are hard to review and hard to bisect. The size itself is ' \
            'not a defect, but it bounds how much confidence any review of it could have had.'
    },
    'repeated-back-merge' => {
      level: 'note',
      text: 'Mainline was merged into this branch repeatedly before it landed',
      help: 'Repeatedly pulling mainline into a branch is how a long-lived branch stays ' \
            'merge-able. It is a reliable symptom of a branch that lived longer than the ' \
            'work justified.'
    },
    'criss-cross-merge' => {
      level: 'note',
      text: 'Branches have merged into each other in both directions',
      help: 'Two branches merged into each other produce multiple merge bases, which makes ' \
            'later merges ambiguous and history hard to reason about. Git has to pick a base, ' \
            'and the one it picks may not be the one you would.'
    },
    'topology-metrics' => {
      level: 'note',
      text: 'Branching topology metrics',
      help: 'Context for a human reading the rest of the report. These are descriptive ' \
            'measurements of the commit graph, not defects, and are deliberately not ' \
            'combined into a score.'
    }
  }.freeze

  # Checked against the deadline between each one, as well as inside their own
  # walks, so an expired run stops paying for the checks it has not started.
  CHECKS = %i[
    unmerged_branches stranded_release_commits merge_findings criss_cross_merges metrics
  ].freeze

  Branch = Struct.new(:ref, :name, :sha, :committed_at, keyword_init: true)
  Finding = Struct.new(:rule_id, :level, :message, :ref, :files, :fingerprint, keyword_init: true)

  # Read-only git access. GIT_OPTIONAL_LOCKS=0 stops git taking the index lock
  # for the refresh some commands would otherwise do.
  class Repo
    ENV_OVERRIDES = { 'GIT_OPTIONAL_LOCKS' => '0' }.freeze

    def initialize(path)
      @path = path
    end

    def capture(*args)
      out, _err, status = Open3.capture3(ENV_OVERRIDES, 'git', '-C', @path, '--no-pager', *args)
      [out, status.success?]
    end

    def lines(*args)
      out, ok = capture(*args)
      return [] unless ok

      out.split("\n").reject(&:empty?)
    end

    def value(*args)
      out, ok = capture(*args)
      return nil unless ok

      stripped = out.strip
      stripped.empty? ? nil : stripped
    end

    def ok?(*args)
      _out, ok = capture(*args)
      ok
    end

    # patch-id reads a diff on stdin, so these are the only places a pipeline is
    # needed. Piping a whole `log -p` through one patch-id call maps every
    # commit in a range in a single pass; doing it per commit is unusably slow
    # on a real repository.
    def patch_ids(*git_args)
      result = {}
      Open3.pipeline_r(
        [ENV_OVERRIDES, 'git', '-C', @path, '--no-pager', *git_args],
        ['git', 'patch-id', '--stable']
      ) do |stdout, _waiters|
        stdout.each_line do |line|
          patch, commit = line.split
          result[patch] = commit if patch && commit
        end
      end
      result
    end
  end

  attr_reader :notes

  def initialize(source, deadline_seconds: DEADLINE_SECONDS)
    @source = source
    @repo = Repo.new(source)
    @deadline = monotonic + deadline_seconds
    @notes = []
    @patch_id_cache = {}
  end

  # Returns the findings, or [] when there is nothing meaningful to say. The
  # two silent cases are deliberate: a source tree with no repository at all
  # (Statica's bread and butter is a zip someone emailed over) and a clone whose
  # history is too incomplete to reason about.
  def run
    return [] unless repository?

    reason = incomplete_history_reason
    if reason
      @notes << "#{reason}, topology checks skipped"
      return []
    end

    findings = []
    CHECKS.each do |check|
      break if expired?

      findings.concat(send(check))
    end
    @notes << 'deadline reached, results are partial' if expired?
    findings
  end

  def repository?
    @repo.ok?('rev-parse', '--git-dir')
  end

  # A shallow or partial clone makes almost every check here produce confident
  # garbage: the merge base is simply absent, so every branch looks unmerged.
  # Refusing is the only honest option.
  def incomplete_history_reason
    return 'history is shallow' if @repo.value('rev-parse', '--is-shallow-repository') == 'true'
    return 'clone is partial' if partial_clone?
    return 'repository has no commits' if @repo.value('rev-parse', '--verify', '--quiet', 'HEAD').nil?

    nil
  end

  # The sarif gem omits an empty results array entirely, which produces the
  # `"results":null` shape that statica already has to special-case for bearer
  # before handing files to `sarif summary`. Emitting an explicit [] keeps a
  # findings-free run from becoming a second instance of that bug.
  def sarif_json(findings)
    document = JSON.parse(to_sarif(findings).to_json)
    document['runs'].each { |run| run['results'] ||= [] }
    JSON.generate(document)
  end

  def to_sarif(findings)
    Sarif::Log.new(
      version: '2.1.0',
      runs: [
        Sarif::Run.new(
          tool: Sarif::Tool.new(driver: Sarif::ToolComponent.new(
            name: TOOL_NAME,
            version: git_version,
            information_uri: 'https://github.com/simpsonjulian/statica',
            organization: 'simpsonjulian',
            rules: RULES.map do |id, rule|
              Sarif::ReportingDescriptor.new(
                id: id,
                short_description: Sarif::MultiformatMessageString.new(text: rule[:text]),
                full_description: Sarif::MultiformatMessageString.new(text: rule[:help]),
                help_uri: "#{HELP_BASE}#{id}"
              )
            end
          )),
          results: findings.map { |finding| to_result(finding) }
        )
      ]
    )
  end

  private

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def expired?
    monotonic > @deadline
  end

  def since_arg
    "--since=#{WINDOW_MONTHS}.months.ago"
  end

  def git_version
    @git_version ||= @repo.value('--version')&.sub(/\Agit version /, '') || 'unknown'
  end

  def partial_clone?
    !@repo.lines('config', '--get-regexp', '^remote\..*\.(promisor|partialclonefilter)$').empty?
  end

  def to_result(finding)
    locations =
      if finding.files && !finding.files.empty?
        finding.files.map do |file|
          Sarif::Location.new(physical_location: Sarif::PhysicalLocation.new(
            artifact_location: Sarif::ArtifactLocation.new(uri: file)
          ))
        end
      else
        # Nothing to point at in the tree. A synthetic physicalLocation would
        # invent a file that does not exist and drag it into the hotspot table,
        # so these carry a logicalLocation naming the ref instead.
        [Sarif::Location.new(logical_locations: [
                               Sarif::LogicalLocation.new(name: finding.ref, fully_qualified_name: finding.ref)
                             ])]
      end

    Sarif::Result.new(
      rule_id: finding.rule_id,
      level: finding.level,
      message: Sarif::Message.new(text: finding.message),
      locations: locations,
      partial_fingerprints: { 'topology/v1' => finding.fingerprint }
    )
  end

  # --- refs -----------------------------------------------------------------

  def all_branches
    @all_branches ||= begin
      remote = refs_under('refs/remotes/')
      # A repository with no remotes is normal for source that arrived as an
      # archive; fall back to local branches rather than reporting nothing.
      remote.empty? ? refs_under('refs/heads/') : remote
    end
  end

  def refs_under(prefix)
    remote_scoped = prefix.start_with?('refs/remotes')
    @repo.lines('for-each-ref',
                '--format=%(refname)%09%(refname:short)%09%(objectname)%09%(committerdate:unix)',
                prefix).filter_map do |line|
      full, short, sha, timestamp = line.split("\t")
      # refs/remotes/origin/HEAD shortens to just "origin", so the symref has to
      # be filtered on its full name or it turns into a phantom branch.
      next if short.nil? || short.empty? || full.to_s.end_with?('/HEAD')

      name = remote_scoped ? short.split('/', 2).last : short
      Branch.new(ref: short, name: name, sha: sha, committed_at: Time.at(timestamp.to_i))
    end.first(MAX_BRANCHES)
  end

  def integration_branches
    @integration_branches ||= all_branches.select { |b| INTEGRATION_CANDIDATES.include?(b.name) }
  end

  def mainline
    @mainline ||= INTEGRATION_CANDIDATES.filter_map do |name|
      integration_branches.find { |b| b.name == name }
    end.first
  end

  def release_branches
    all_branches.select { |b| release_line?(b.name) }
  end

  def release_line?(name)
    RELEASE_PATTERNS.any? { |pattern| name.match?(pattern) }
  end

  def excluded?(name)
    EXCLUDED_PATTERNS.any? { |pattern| name.match?(pattern) }
  end

  def days_between(later, earlier)
    ((later - earlier) / 86_400.0).floor
  end

  def commit_time(rev)
    timestamp = @repo.value('log', '-1', '--format=%ct', rev)
    timestamp && Time.at(timestamp.to_i)
  end

  def parents_of(sha)
    @repo.value('rev-list', '--parents', '-n', '1', sha).to_s.split[1..] || []
  end

  def count_commits(range)
    @repo.value('rev-list', '--count', range).to_i
  end

  # --- check 1: branches that never merge down ------------------------------

  def unmerged_branches
    return [] if integration_branches.empty?

    findings = []
    candidates = all_branches.reject { |b| INTEGRATION_CANDIDATES.include?(b.name) || excluded?(b.name) }

    candidates.each do |branch|
      break if expired?

      days = days_between(Time.now, branch.committed_at)
      level = branch_level(days)
      next if level.nil?

      missing = targets_for(branch).reject { |target| merged_into?(branch, target) }
      next if missing.empty?

      findings << unmerged_finding(branch, missing, days)
      findings.concat(back_merge_finding(branch))
    end

    findings
  end

  # Mainline is deliberately not a target for release lines: check 2 owns that
  # relationship and describes it far better, naming the actual commits rather
  # than just saying the branch never landed.
  def targets_for(branch)
    return integration_branches unless release_line?(branch.name)

    integration_branches.reject { |target| target.ref == mainline&.ref }
  end

  def branch_level(days)
    BRANCH_LEVELS.each { |threshold, level| return level if days >= threshold }
    nil
  end

  def unmerged_finding(branch, missing, days)
    # Counted against a branch it is actually missing from. Measuring against
    # mainline instead reports "0 commits ahead" for a branch that landed on
    # main but never reached develop, which reads as a contradiction.
    reference = missing.first
    ahead = count_commits("#{reference.ref}..#{branch.ref}")
    targets = missing.map(&:name).join(', ')
    Finding.new(
      rule_id: 'branch-never-merged',
      level: branch_level(days),
      message: "Branch '#{branch.name}' was last committed to #{days} days ago and has never " \
               "been merged into #{targets}. It is #{ahead} commit#{'s' unless ahead == 1} " \
               "ahead of #{reference.name}. Ancestry, patch ID and squash detection all agree " \
               'it never landed.',
      ref: branch.ref,
      fingerprint: "branch-never-merged:#{branch.name}"
    )
  end

  # Ancestry alone reports every squash-merged branch as unmerged, and squash
  # merges are the default on most forges, so this layers three tests. git
  # cherry catches rebase and cherry-pick, where per-commit patch IDs survive.
  # It does *not* catch a squashed multi-commit branch, because the squash
  # collapses N commits into one whose patch ID matches none of them - that
  # needs the branch's cumulative diff compared against mainline's commits.
  def merged_into?(branch, target)
    return true if @repo.ok?('merge-base', '--is-ancestor', branch.sha, target.ref)
    return true if cherry_all_upstream?(branch, target)

    squashed_into?(branch, target)
  end

  def cherry_all_upstream?(branch, target)
    out, ok = @repo.capture('cherry', target.ref, branch.ref)
    return false unless ok

    lines = out.split("\n").reject(&:empty?)
    return false if lines.empty?

    lines.none? { |line| line.start_with?('+') }
  end

  def squashed_into?(branch, target)
    base = @repo.value('merge-base', target.ref, branch.ref)
    return false if base.nil?

    cumulative = @repo.patch_ids('diff', base, branch.ref).keys.first
    return false if cumulative.nil?

    patch_ids_for(target).key?(cumulative)
  end

  def patch_ids_for(target)
    @patch_id_cache[target.ref] ||= @repo.patch_ids(
      'log', '-p', '--no-merges', "--max-count=#{MAX_PATCH_ID_COMMITS}", since_arg, target.ref
    )
  end

  # Only computed for branches already known to be unmerged, which keeps an
  # otherwise quadratic walk nearly free.
  def back_merge_finding(branch)
    main = mainline
    return [] if main.nil?

    base = @repo.value('merge-base', main.ref, branch.ref)
    return [] if base.nil?

    count = @repo.lines('rev-list', '--merges', "--max-count=#{MAX_MERGES}",
                        "#{base}..#{branch.ref}").count do |merge|
      parents = parents_of(merge)
      parents.length == 2 && @repo.ok?('merge-base', '--is-ancestor', parents[1], main.ref)
    end
    return [] if count < BACK_MERGE_THRESHOLD

    [Finding.new(
      rule_id: 'repeated-back-merge',
      level: 'note',
      message: "Branch '#{branch.name}' merged #{main.name} into itself #{count} times without " \
               'ever merging back. Keeping a branch merge-able for that long usually means it ' \
               'should have been split.',
      ref: branch.ref,
      fingerprint: "repeated-back-merge:#{branch.name}"
    )]
  end

  # --- check 2: commits stranded on a release line --------------------------

  def stranded_release_commits
    main = mainline
    return [] if main.nil?

    findings = []
    release_branches.each do |branch|
      break if expired?

      # --cherry-pick is load-bearing: without it every commit that was
      # cherry-picked to mainline rather than merged is reported as missing,
      # which on a real release line is most of them.
      shas = @repo.lines('rev-list', '--right-only', '--cherry-pick', '--no-merges',
                         "--max-count=#{MAX_MERGES}", since_arg,
                         "#{main.ref}...#{branch.ref}")
      next if shas.empty?

      findings << stranded_finding(branch, main, shas)
    end
    findings
  end

  def stranded_finding(branch, main, shas)
    subjects = shas.first(5).filter_map { |sha| @repo.value('log', '-1', '--format=%h %s', sha) }
    more = shas.length > subjects.length ? " (and #{shas.length - subjects.length} more)" : ''
    Finding.new(
      rule_id: 'release-commit-not-forward-ported',
      level: shas.length > 10 ? 'error' : 'warning',
      message: "#{shas.length} commit#{'s' unless shas.length == 1} on '#{branch.name}' " \
               "#{shas.length == 1 ? 'is' : 'are'} not on #{main.name} and #{shas.length == 1 ? 'was' : 'were'} " \
               "not cherry-picked there: #{subjects.join('; ')}#{more}. These changes will be " \
               'absent from the next release cut from mainline.',
      ref: branch.ref,
      fingerprint: "release-commit-not-forward-ported:#{branch.name}"
    )
  end

  # --- check 3: expensive merges --------------------------------------------

  def merge_findings
    return [] if integration_branches.empty?

    refs = integration_branches.map(&:ref)
    findings = []
    @repo.lines('rev-list', '--merges', "--max-count=#{MAX_MERGES}", since_arg, *refs).each do |sha|
      break if expired?

      findings.concat(analyse_merge(sha))
    end
    findings
  end

  def analyse_merge(sha)
    parents = parents_of(sha)
    # Octopus merges have no single "other side" to measure divergence against.
    return [] unless parents.length == 2

    base = @repo.value('merge-base', parents[0], parents[1])
    return [] if base.nil?

    left = count_commits("#{base}..#{parents[0]}")
    right = count_commits("#{base}..#{parents[1]}")
    left_files = Set.new(@repo.lines('diff', '--name-only', base, parents[0]))
    right_files = Set.new(@repo.lines('diff', '--name-only', base, parents[1]))
    overlap = (left_files & right_files).to_a.sort

    findings = []
    findings.concat(divergence_finding(sha, base, left, right))
    findings.concat(overlap_finding(sha, left_files, right_files, overlap))
    findings.concat(size_finding(sha, parents[0]))
    findings
  end

  def divergence_finding(sha, base, left, right)
    merged_at = commit_time(sha)
    based_at = commit_time(base)
    return [] if merged_at.nil? || based_at.nil?

    days = days_between(merged_at, based_at)
    return [] if days < DIVERGENCE_DAYS
    return [] if [left, right].min < DIVERGENCE_MIN_COMMITS

    [Finding.new(
      rule_id: 'merge-high-divergence',
      level: days >= DIVERGENCE_DAYS_HIGH ? 'error' : 'warning',
      message: "Merge #{short(sha)} joined two sides that had diverged for #{days} days, with " \
               "#{left} and #{right} commits developed in parallel. The merge is where this " \
               'surfaced; the cost was incurred over the preceding weeks.',
      ref: short(sha),
      fingerprint: "merge-high-divergence:#{sha}"
    )]
  end

  def overlap_finding(sha, left_files, right_files, overlap)
    smaller = [left_files.size, right_files.size].min
    return [] if smaller.zero? || overlap.size < OVERLAP_MIN_FILES

    ratio = overlap.size.to_f / smaller
    return [] if ratio < OVERLAP_MIN_RATIO

    capped = overlap.first(OVERLAP_MAX_LOCATIONS)
    truncated = overlap.size > capped.size ? " Showing #{capped.size} of #{overlap.size}." : ''
    [Finding.new(
      rule_id: 'merge-high-overlap',
      level: overlap.size >= OVERLAP_HIGH_FILES ? 'error' : 'warning',
      message: "Merge #{short(sha)} had to reconcile #{overlap.size} files changed on both " \
               "sides (#{(ratio * 100).round}% of the smaller side).#{truncated}",
      ref: short(sha),
      files: capped,
      fingerprint: "merge-high-overlap:#{sha}"
    )]
  end

  def size_finding(sha, first_parent)
    rows = @repo.lines('diff', '--numstat', first_parent, sha)
    return [] if rows.empty?

    changed = rows.sum do |row|
      added, deleted, = row.split("\t")
      added.to_i + deleted.to_i
    end
    return [] if rows.length < BIG_MERGE_FILES && changed < BIG_MERGE_LINES

    [Finding.new(
      rule_id: 'merge-large',
      level: 'note',
      message: "Merge #{short(sha)} integrated #{rows.length} files and #{changed} changed " \
               'lines in one step.',
      ref: short(sha),
      fingerprint: "merge-large:#{sha}"
    )]
  end

  def short(sha)
    sha[0, 12]
  end

  # --- criss-cross ----------------------------------------------------------

  # Two branches merged into each other leave more than one merge base, which
  # is both the symptom and the reason it matters. One command per pair, and
  # only over integration branches, so the pairwise walk stays small.
  def criss_cross_merges
    pairs = integration_branches.combination(2).to_a
    findings = []
    pairs.each do |left, right|
      break if expired?

      bases = @repo.lines('merge-base', '--all', left.ref, right.ref)
      next if bases.length < 2

      findings << Finding.new(
        rule_id: 'criss-cross-merge',
        level: 'note',
        message: "'#{left.name}' and '#{right.name}' have #{bases.length} merge bases, meaning " \
                 'they have been merged into each other in both directions. Future merges ' \
                 'between them will pick one base ambiguously.',
        ref: "#{left.name}...#{right.name}",
        fingerprint: "criss-cross-merge:#{left.name}:#{right.name}"
      )
    end
    findings
  end

  # --- check 4: informational metrics ---------------------------------------

  def metrics
    main = mainline
    return [] if main.nil?

    total = count_commits_since(main.ref)
    return [] if total.zero?

    merges = @repo.value('rev-list', '--count', '--merges', since_arg, main.ref).to_i
    lifetimes = branch_lifetimes
    lines = [
      "Over the last #{WINDOW_MONTHS} months on #{main.name}: #{total} commits, #{merges} of " \
      "them merges (#{(merges * 100.0 / total).round}%).",
      "#{all_branches.length} branches currently exist."
    ]
    lines << lifetime_line(lifetimes) unless lifetimes.empty?
    lines << "Maximum branches in flight at once: #{max_concurrent(lifetimes)}." unless lifetimes.empty?

    [Finding.new(
      rule_id: 'topology-metrics',
      level: 'note',
      message: lines.join(' '),
      ref: main.name,
      fingerprint: 'topology-metrics'
    )]
  end

  def count_commits_since(ref)
    @repo.value('rev-list', '--count', since_arg, ref).to_i
  end

  def lifetime_line(lifetimes)
    days = lifetimes.map { |span| span[:days] }.sort
    mean = (days.sum.to_f / days.length).round
    p90 = days[(0.9 * (days.length - 1)).round]
    "Branch lifetime across #{days.length} branches: mean #{mean} days, p90 #{p90} days."
  end

  # first commit since the merge base -> last commit, per branch
  def branch_lifetimes
    @branch_lifetimes ||= begin
      main = mainline
      spans = []
      all_branches.each do |branch|
        break if expired?
        next if main.nil? || branch.ref == main.ref
        # Same exclusions as check 1: a fleet of single-commit bot branches
        # drags the mean to zero and describes the bot, not the workflow.
        next if excluded?(branch.name) || INTEGRATION_CANDIDATES.include?(branch.name)

        base = @repo.value('merge-base', main.ref, branch.ref)
        next if base.nil?

        stamps = @repo.lines('log', '--format=%ct', "#{base}..#{branch.ref}").map(&:to_i)
        next if stamps.empty?

        spans << { start: stamps.min, finish: stamps.max,
                   days: ((stamps.max - stamps.min) / 86_400.0).floor }
      end
      spans
    end
  end

  # Sweep line over [first commit, last commit] intervals.
  def max_concurrent(lifetimes)
    events = lifetimes.flat_map { |span| [[span[:start], 1], [span[:finish], -1]] }
    # Close before open at the same instant, so a branch that ends exactly when
    # another starts is not counted as concurrent.
    events.sort_by! { |time, delta| [time, delta] }
    running = 0
    events.map { |_time, delta| running += delta }.max || 0
  end
end
