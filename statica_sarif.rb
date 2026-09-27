# frozen_string_literal: true

require 'find'
require 'json'
require 'sarif'
require 'time'

# Shared SARIF plumbing for the scanners in tools.d. A scanner registers its rules, adds
# results against them and calls emit; the quirks of sarif-ruby live here rather than in
# seven copies.
module Statica
  INFORMATION_URI = 'https://github.com/simpsonjulian/statica'

  # Dependency, build and VCS trees. Scanning these reports dead code, stale frameworks
  # and disabled code that belongs to somebody else and cannot be deleted here.
  EXCLUDES = %w[
    .git .hg .svn .bundle .gradle .idea .vscode .venv venv
    node_modules bower_components jspm_packages vendor packages
    target build dist out bin obj coverage tmp log
  ].freeze

  # Files under root with excluded directories pruned, yielding the absolute path and
  # the path relative to root, which is what a SARIF artifactLocation wants.
  def self.each_file(root, excludes: EXCLUDES)
    Find.find(root) do |path|
      if File.directory?(path)
        Find.prune if excludes.include?(File.basename(path))
        next
      end
      yield path, path.delete_prefix("#{root}/").delete_prefix('./')
    end
  end

  # One SARIF run. Levels are a property of the rule, so a result inherits its rule's
  # level unless it overrides it.
  class Report
    Rule = Struct.new(:id, :description, :level, :name, :full, :help_uri)

    attr_reader :results

    def initialize(driver, version: '0.1.0')
      @driver = driver
      @version = version
      @rules = {}
      @results = []
      @invocation = {}
      @provenance = nil
    end

    def rule(id, description, level: 'note', name: nil, full: nil, help_uri: nil)
      @rules[id] = Rule.new(id, description, level, name, full, help_uri)
    end

    def invocation(**properties)
      @invocation = properties
    end

    def version_control(repository_uri:, branch: nil)
      @provenance = Sarif::VersionControlDetails.new(repository_uri: repository_uri, branch: branch)
    end

    # A finding: pass uri (with optional line and end_line) for somewhere in a file, or
    # logical for a thing with no file at all, such as a branch or a commit.
    def add(rule_id, text, uri: nil, line: nil, end_line: nil, logical: nil, kind: 'logical',
            level: nil, properties: {}, fingerprints: nil)
      @results << Sarif::Result.new(
        rule_id: rule_id, level: level || @rules[rule_id]&.level || 'note',
        message: Sarif::Message.new(text: text),
        locations: [location(uri, line, end_line, logical, kind)].compact,
        partial_fingerprints: fingerprints,
        properties: properties
      )
    end

    def emit(io = $stdout)
      io.puts JSON.pretty_generate(document)
    end

    private

    # sarif-tools rejects a run outright when a result has neither a file nor a logical
    # name, and reads a logical location only through fullyQualifiedName.
    def location(uri, line, end_line, logical, kind)
      if uri
        Sarif::Location.new(physical_location: Sarif::PhysicalLocation.new(
          artifact_location: Sarif::ArtifactLocation.new(uri: uri), region: region(line, end_line)
        ))
      elsif logical
        Sarif::Location.new(logical_locations: [
                              Sarif::LogicalLocation.new(name: logical, fully_qualified_name: logical, kind: kind)
                            ])
      end
    end

    # A region needs a real line. Line 0 is not valid SARIF, and an end before the start
    # is worse than no end at all.
    def region(line, end_line)
      return nil unless line.to_i.positive?

      finish = end_line.to_i >= line.to_i ? end_line.to_i : nil
      Sarif::Region.new(start_line: line.to_i, end_line: finish)
    end

    def descriptors
      @rules.values.map do |r|
        Sarif::ReportingDescriptor.new(
          id: r.id, name: r.name,
          short_description: Sarif::MultiformatMessageString.new(text: r.description),
          full_description: r.full && Sarif::MultiformatMessageString.new(text: r.full),
          help_uri: r.help_uri,
          default_configuration: Sarif::ReportingConfiguration.new(level: r.level)
        )
      end
    end

    def log
      Sarif::Log.new(
        schema_uri: 'https://json.schemastore.org/sarif-2.1.0.json', version: '2.1.0',
        runs: [Sarif::Run.new(
          tool: Sarif::Tool.new(driver: Sarif::ToolComponent.new(
            name: @driver, version: @version, information_uri: INFORMATION_URI, rules: descriptors
          )),
          invocations: [Sarif::Invocation.new(execution_successful: true,
                                              end_time_utc: Time.now.utc.iso8601,
                                              properties: @invocation)],
          version_control_provenance: @provenance && [@provenance],
          results: @results
        )]
      )
    end

    # Two sarif-ruby gaps. It drops "results" when the array is empty, and sarif-tools
    # then dies with KeyError: 'results', taking down statica's whole console summary
    # rather than one report. It also serialises ReportingConfiguration as {}, losing
    # every rule's default level.
    def document
      doc = log.to_h
      doc['runs'].each do |run|
        run['results'] ||= []
        run.dig('tool', 'driver', 'rules')&.each do |descriptor|
          level = @rules[descriptor['id']]&.level
          descriptor['defaultConfiguration'] = { 'level' => level } if level
        end
      end
      doc
    end
  end
end
