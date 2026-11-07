# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# The scc-hotspots and scc-coupling scanners, run end to end against a throwaway git
# repository. scc itself is replaced by a stub on PATH that prints canned JSON in the
# shape scc 4.1 emits, so these specs pin the SARIF mapping rather than scc's scoring.
RSpec.describe 'scc scanners' do
  hotspots = {
    'report' => 'hotspots',
    'files' => [
      { 'file' => 'app/big.rb', 'language' => 'Ruby', 'complexity' => 30, 'commits' => 12,
        'linesChanged' => 400, 'authors' => 3, 'codeChurn' => 200, 'score' => 100 },
      { 'file' => 'vendor/lib.rb', 'language' => 'Ruby', 'complexity' => 50, 'commits' => 9,
        'linesChanged' => 300, 'authors' => 1, 'codeChurn' => 100, 'score' => 90 },
      { 'file' => 'app/gone.rb', 'language' => 'Ruby', 'complexity' => 20, 'commits' => 5,
        'linesChanged' => 100, 'authors' => 1, 'codeChurn' => 50, 'score' => 40 },
      { 'file' => 'README.md', 'language' => 'Markdown', 'complexity' => 0, 'commits' => 8,
        'linesChanged' => 50, 'authors' => 2, 'codeChurn' => 0, 'score' => 3 }
    ]
  }

  coupling = {
    'report' => 'coupling',
    'pairs' => [
      { 'fileA' => 'app/big.rb', 'fileB' => 'spec/big_spec.rb', 'shared' => 9,
        'commitsA' => 12, 'commitsB' => 10, 'degree' => 69.2 },
      { 'fileA' => 'app/big.rb', 'fileB' => 'app/small.rb', 'shared' => 6,
        'commitsA' => 12, 'commitsB' => 7, 'degree' => 46.2 },
      { 'fileA' => 'app/big.rb', 'fileB' => 'README.md', 'shared' => 2,
        'commitsA' => 12, 'commitsB' => 8, 'degree' => 30 },
      { 'fileA' => 'app/small.rb', 'fileB' => 'README.md', 'shared' => 4,
        'commitsA' => 7, 'commitsB' => 8, 'degree' => 10 }
    ]
  }

  around do |example|
    Dir.mktmpdir do |tmp|
      @repo = File.join(tmp, 'repo')
      @bin = File.join(tmp, 'bin')
      FileUtils.mkdir_p([@bin, "#{@repo}/app", "#{@repo}/spec", "#{@repo}/vendor"])
      %w[app/big.rb app/small.rb spec/big_spec.rb vendor/lib.rb README.md].each do |f|
        File.write(File.join(@repo, f), "x = 1\n")
      end
      git('init', '-q')
      git('add', '.')
      git('-c', 'user.name=t', '-c', 'user.email=t@example.com', 'commit', '-q', '-m', 'init')
      example.run
    end
  end

  def git(*args)
    _, err, status = Open3.capture3('git', '-C', @repo, *args)
    raise err unless status.success?
  end

  # Writes a stub scc that answers --version and prints the canned report for whichever
  # report flag it is given, recording its arguments for inspection.
  def stub_scc(reports)
    reports.each { |flag, body| File.write(File.join(@bin, "#{flag.delete_prefix('--')}.json"), JSON.generate(body)) }
    File.write(File.join(@bin, 'scc'), <<~SH)
      #!/bin/sh
      echo "$@" >> "#{@bin}/args"
      [ "$1" = "--version" ] && { echo "scc version 4.1.0"; exit 0; }
      cat "#{@bin}/${1#--}.json"
    SH
    File.chmod(0o755, File.join(@bin, 'scc'))
  end

  def scan(tool, dir, *args)
    env = { 'PATH' => "#{@bin}:#{ENV.fetch('PATH')}" }
    out, err, status = Open3.capture3(env, RbConfig.ruby, File.expand_path("../tools.d/#{tool}", __dir__), *args, dir)
    raise "#{tool} failed: #{err}" unless status.success?

    JSON.parse(out).dig('runs', 0)
  end

  def uris(run)
    run['results'].map { |r| r.dig('locations', 0, 'physicalLocation', 'artifactLocation', 'uri') }
  end

  describe 'scc-hotspots' do
    before { stub_scc('--hotspots' => hotspots) }

    it 'reports scored files, skipping excluded trees and deleted files' do
      run = scan('scc-hotspots', @repo)

      expect(uris(run)).to eq(%w[app/big.rb README.md])
      expect(run['results'].first['properties']).to include('score' => 100, 'complexity' => 30)
      expect(run.dig('tool', 'driver', 'version')).to eq('4.1.0')
    end

    it 'drops files under --min-score' do
      expect(uris(scan('scc-hotspots', @repo, '--min-score', '5'))).to eq(%w[app/big.rb])
    end

    it 'reports paths relative to a scanned subdirectory, not the repository root' do
      expect(uris(scan('scc-hotspots', File.join(@repo, 'app')))).to eq(%w[big.rb])
    end

    it 'windows scc by the commits since --since' do
      scan('scc-hotspots', @repo)

      expect(File.read(File.join(@bin, 'args'))).to include('--hotspots --format json --depth 1 .')
    end

    it 'reports nothing, without asking scc for all history, when the window is empty' do
      _, err, status = Open3.capture3({ 'GIT_COMMITTER_DATE' => '2000-01-01T00:00:00Z' },
                                      'git', '-C', @repo, '-c', 'user.name=t', '-c', 'user.email=t@example.com',
                                      'commit', '-q', '--amend', '--no-edit')
      raise err unless status.success?

      run = scan('scc-hotspots', @repo)

      expect(run['results']).to eq([])
      expect(File.read(File.join(@bin, 'args'))).not_to include('--hotspots')
    end
  end

  describe 'scc-coupling' do
    before { stub_scc('--coupling-weighted' => coupling, '--coupling' => coupling) }

    it 'reports coupled pairs with the second file as a related location' do
      run = scan('scc-coupling', @repo)

      expect(run['results'].size).to eq(1)
      result = run['results'].first
      expect(uris(run)).to eq(%w[app/big.rb])
      expect(result.dig('relatedLocations', 0, 'physicalLocation', 'artifactLocation', 'uri')).to eq('app/small.rb')
      expect(result['partialFingerprints']).to eq('filePair/v1' => 'app/big.rb|app/small.rb')
    end

    it 'skips a file paired with its own test, and pairs under the thresholds' do
      reported = scan('scc-coupling', @repo)['results'].map { |r| r.dig('properties', 'coupledWith') }

      expect(reported).not_to include('spec/big_spec.rb', 'README.md')
    end

    it 'loosens with the thresholds' do
      run = scan('scc-coupling', @repo, '--min-shared', '1', '--min-degree', '0')

      expect(run['results'].map { |r| r.dig('properties', 'coupledWith') }).to eq(%w[app/small.rb README.md README.md])
    end

    it 'uses weighted coupling unless told not to' do
      scan('scc-coupling', @repo)
      scan('scc-coupling', @repo, '--no-weighted')

      expect(File.read(File.join(@bin, 'args')).lines.grep(/coupling/).map { |l| l.split.first })
        .to eq(%w[--coupling-weighted --coupling])
    end
  end
end
