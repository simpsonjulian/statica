# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../topology_analyzer'
require_relative 'support/git_fixture'

RSpec.describe TopologyAnalyzer do
  around do |example|
    Dir.mktmpdir('statica-topology') do |dir|
      @tmp = dir
      example.run
    end
  end

  def repo_at(name = 'repo')
    File.join(@tmp, name)
  end

  def findings_for(path)
    described_class.new(path).run
  end

  def rule_ids(findings)
    findings.map(&:rule_id)
  end

  # Every fixture starts from a mainline with enough shared files that a merge
  # can plausibly overlap.
  def base_repo(name = 'repo')
    fixture = GitFixture.new(repo_at(name))
    files = (1..12).to_h { |i| ["src/f#{i}.rb", "original #{i}\n"] }
    fixture.commit('base', files: files, days_ago: 365)
    fixture
  end

  def touch_all(prefix, count: 12)
    (1..count).to_h { |i| ["src/f#{i}.rb", "#{prefix} #{i}\n"] }
  end

  describe 'degrading when there is no usable history' do
    it 'produces nothing at all for a directory with no .git' do
      plain = File.join(@tmp, 'plain')
      FileUtils.mkdir_p(plain)
      File.write(File.join(plain, 'app.rb'), 'puts 1')

      analyzer = described_class.new(plain)

      expect(analyzer.run).to be_empty
      expect(analyzer.notes).to be_empty
    end

    it 'still emits a valid, empty SARIF document when there is no repository' do
      plain = File.join(@tmp, 'plain')
      FileUtils.mkdir_p(plain)
      analyzer = described_class.new(plain)

      parsed = JSON.parse(analyzer.sarif_json(analyzer.run))

      expect(parsed['runs'][0]['results']).to eq([])
      expect(parsed['runs'][0]['tool']['driver']['name']).to eq('topology')
    end

    it 'skips the checks on a shallow clone rather than guessing' do
      fixture = base_repo
      fixture.create_branch('feature/abandoned')
      fixture.commit('abandoned work', days_ago: 200)
      fixture.checkout('main')
      fixture.commit('mainline moves on', days_ago: 100)
      fixture.publish!

      shallow = fixture.shallow_clone(File.join(@tmp, 'shallow'))
      analyzer = described_class.new(shallow)

      expect(analyzer.run).to be_empty
      expect(analyzer.notes.join).to match(/shallow/)
    end

    it 'reports an empty repository as incomplete rather than crashing' do
      empty = File.join(@tmp, 'empty')
      GitFixture.new(empty)

      expect(findings_for(empty)).to be_empty
    end
  end

  describe 'branches that never merge down' do
    it 'reports a genuinely abandoned branch' do
      fixture = base_repo
      fixture.create_branch('feature/abandoned')
      fixture.commit('work nobody landed', days_ago: 200)
      fixture.checkout('main')
      fixture.commit('mainline moves on', days_ago: 100)
      fixture.publish!

      findings = findings_for(repo_at)
      abandoned = findings.select { |f| f.rule_id == 'branch-never-merged' }

      expect(abandoned.map(&:ref)).to eq(['origin/feature/abandoned'])
      expect(abandoned.first.message).to match(/never been merged into main/)
    end

    it 'does not report a squash-merged branch' do
      fixture = base_repo
      fixture.create_branch('feature/squashed')
      fixture.commit('part one', days_ago: 200)
      fixture.commit('part two', days_ago: 200)
      fixture.checkout('main')
      fixture.squash_merge('feature/squashed', days_ago: 190)
      fixture.publish!

      expect(rule_ids(findings_for(repo_at))).not_to include('branch-never-merged')
    end

    it 'does not report a rebase-merged branch' do
      fixture = base_repo
      fixture.create_branch('feature/rebased')
      fixture.commit('part one', days_ago: 200)
      fixture.commit('part two', days_ago: 200)
      fixture.checkout('main')
      fixture.commit('mainline moves first', days_ago: 195)
      fixture.rebase_merge('feature/rebased', days_ago: 190)
      fixture.publish!

      expect(rule_ids(findings_for(repo_at))).not_to include('branch-never-merged')
    end

    it 'does not report a branch that is too young to have landed yet' do
      fixture = base_repo
      fixture.create_branch('feature/in-progress')
      fixture.commit('still working', days_ago: 3)
      fixture.checkout('main')
      fixture.publish!

      expect(rule_ids(findings_for(repo_at))).not_to include('branch-never-merged')
    end

    it 'does not report branches that are conventional dead ends' do
      fixture = base_repo
      %w[spike/idea archive/old wip/scratch].each do |name|
        fixture.checkout('main')
        fixture.create_branch(name)
        fixture.commit("work on #{name}", days_ago: 300)
      end
      fixture.checkout('main')
      fixture.publish!

      expect(rule_ids(findings_for(repo_at))).not_to include('branch-never-merged')
    end

    it 'escalates severity with how long the branch has been sitting' do
      fixture = base_repo
      fixture.create_branch('feature/ancient')
      fixture.commit('long forgotten', days_ago: 300)
      fixture.checkout('main')
      fixture.create_branch('feature/recent')
      fixture.commit('recently stalled', days_ago: 45)
      fixture.checkout('main')
      fixture.publish!

      levels = findings_for(repo_at)
               .select { |f| f.rule_id == 'branch-never-merged' }
               .to_h { |f| [f.ref, f.level] }

      expect(levels['origin/feature/ancient']).to eq('error')
      expect(levels['origin/feature/recent']).to eq('note')
    end

    it 'does not treat the origin/HEAD symref as a branch' do
      fixture = base_repo
      fixture.commit('mainline work', days_ago: 200)
      fixture.publish!
      # refs/remotes/origin/HEAD shortens to "origin", so filtering on the short
      # name alone lets it through as a phantom branch.
      fixture.git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main')

      metrics = findings_for(repo_at).find { |f| f.rule_id == 'topology-metrics' }

      expect(metrics.message).to match(/\b1 branches currently exist/)
    end

    it 'counts commits ahead of a branch it is actually missing from' do
      fixture = base_repo
      fixture.create_branch('develop')
      fixture.checkout('main')
      fixture.commit('mainline moves ahead', days_ago: 100)
      fixture.create_branch('feature/landed-on-main')
      fixture.commit('feature work', days_ago: 90)
      fixture.checkout('main')
      fixture.merge('feature/landed-on-main', days_ago: 89)
      fixture.publish!

      finding = findings_for(repo_at)
                .find { |f| f.rule_id == 'branch-never-merged' && f.ref.include?('landed-on-main') }

      expect(finding.message).to match(/never been merged into develop/)
      expect(finding.message).to match(/2 commits ahead of develop/)
    end

    it 'falls back to local branches when the repository has no remote refs' do
      fixture = base_repo
      fixture.create_branch('feature/abandoned')
      fixture.commit('work nobody landed', days_ago: 200)
      fixture.checkout('main')

      refs = findings_for(repo_at)
             .select { |f| f.rule_id == 'branch-never-merged' }
             .map(&:ref)

      expect(refs).to eq(['feature/abandoned'])
    end
  end

  describe 'commits stranded on a release line' do
    it 'reports a fix that never made it back to mainline' do
      fixture = base_repo
      fixture.create_branch('release/1.8')
      fixture.commit('urgent fix on the release line', days_ago: 60)
      fixture.checkout('main')
      fixture.commit('unrelated mainline work', days_ago: 50)
      fixture.publish!

      stranded = findings_for(repo_at).select { |f| f.rule_id == 'release-commit-not-forward-ported' }

      expect(stranded.map(&:ref)).to eq(['origin/release/1.8'])
      expect(stranded.first.message).to match(/urgent fix on the release line/)
    end

    it 'does not report a commit that was cherry-picked to mainline' do
      fixture = base_repo
      fixture.create_branch('release/1.9')
      sha = fixture.commit('fix that was forward-ported', days_ago: 60)
      fixture.checkout('main')
      fixture.cherry_pick(sha, days_ago: 55)
      fixture.publish!

      expect(rule_ids(findings_for(repo_at))).not_to include('release-commit-not-forward-ported')
    end
  end

  describe 'expensive merges' do
    it 'reports a long-lived branch with heavy file overlap' do
      fixture = base_repo
      fixture.create_branch('feature/long-lived')
      6.times do |i|
        fixture.commit("feature change #{i}", files: touch_all("feature #{i}"), days_ago: 100 - i)
      end
      fixture.checkout('main')
      6.times do |i|
        fixture.commit("mainline change #{i}", files: touch_all("mainline #{i}"), days_ago: 100 - i)
      end
      fixture.merge('feature/long-lived', days_ago: 20, resolve: true)
      fixture.publish!

      findings = findings_for(repo_at)

      expect(rule_ids(findings)).to include('merge-high-divergence', 'merge-high-overlap')
    end

    it 'carries the overlapping file paths so they reach the hotspot analysis' do
      fixture = base_repo
      fixture.create_branch('feature/long-lived')
      6.times do |i|
        fixture.commit("feature change #{i}", files: touch_all("feature #{i}"), days_ago: 100 - i)
      end
      fixture.checkout('main')
      6.times do |i|
        fixture.commit("mainline change #{i}", files: touch_all("mainline #{i}"), days_ago: 100 - i)
      end
      fixture.merge('feature/long-lived', days_ago: 20, resolve: true)
      fixture.publish!

      overlap = findings_for(repo_at).find { |f| f.rule_id == 'merge-high-overlap' }

      expect(overlap.files).to include('src/f1.rb')
      expect(overlap.files.length).to be <= described_class::OVERLAP_MAX_LOCATIONS
    end

    it 'produces nothing for a clean, short-lived branch merge' do
      fixture = base_repo
      fixture.commit('mainline settles', days_ago: 30)
      fixture.create_branch('feature/tidy')
      fixture.commit('one small change', files: { 'src/f1.rb' => "tidy\n" }, days_ago: 5)
      fixture.checkout('main')
      fixture.merge('feature/tidy', days_ago: 4)
      fixture.publish!

      substantive = findings_for(repo_at).reject { |f| f.rule_id == 'topology-metrics' }

      expect(substantive).to be_empty
    end
  end

  describe 'SARIF mapping' do
    it 'gives ref-scoped findings a logicalLocation and no invented file' do
      fixture = base_repo
      fixture.create_branch('feature/abandoned')
      fixture.commit('work nobody landed', days_ago: 200)
      fixture.checkout('main')
      fixture.publish!

      analyzer = described_class.new(repo_at)
      parsed = JSON.parse(analyzer.sarif_json(analyzer.run))
      result = parsed['runs'][0]['results'].find { |r| r['ruleId'] == 'branch-never-merged' }

      expect(result['locations'][0]).not_to have_key('physicalLocation')
      expect(result['locations'][0]['logicalLocations'][0]['name']).to eq('origin/feature/abandoned')
    end

    it 'sets a stable partial fingerprint that survives a re-run' do
      fixture = base_repo
      fixture.create_branch('feature/abandoned')
      fixture.commit('work nobody landed', days_ago: 200)
      fixture.checkout('main')
      fixture.publish!

      first = described_class.new(repo_at).run.map(&:fingerprint)
      # A new commit on mainline must not re-open triage on the stale branch.
      fixture.commit('unrelated mainline work', days_ago: 1)
      fixture.publish!
      second = described_class.new(repo_at).run.map(&:fingerprint)

      expect(second).to include(*first.reject { |f| f == 'topology-metrics' })
    end

    it 'declares every emitted rule with a help URI and an explanation' do
      analyzer = described_class.new(repo_at('none'))
      rules = JSON.parse(analyzer.sarif_json([]))['runs'][0]['tool']['driver']['rules']

      expect(rules.map { |r| r['id'] }).to match_array(described_class::RULES.keys)
      expect(rules).to all(include('helpUri'))
      expect(rules.map { |r| r['fullDescription']['text'] }).to all(be_a(String))
    end
  end

  describe 'bounded runtime' do
    it 'stops walking once the deadline has passed' do
      fixture = base_repo
      fixture.create_branch('feature/abandoned')
      fixture.commit('work nobody landed', days_ago: 200)
      fixture.checkout('main')
      fixture.publish!

      analyzer = described_class.new(repo_at, deadline_seconds: -1)

      expect(analyzer.run).to be_empty
      expect(analyzer.notes.join).to match(/deadline/)
    end
  end
end
