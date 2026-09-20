#!/usr/bin/env ruby
# frozen_string_literal: true

require 'English'
require 'json'
require 'ostruct'
require 'erb'
require 'cgi/util'
require 'sarif'
require_relative 'graph_analyzer'

# renders sarif findings into HTML and writes to disk
class HtmlReport
  attr_reader :results, :severities, :graph_analyzer

  def file_type_check(sarif_file)
    # Check if the file is a SARIF file by its extension
    File.extname(sarif_file).casecmp('.sarif').zero? || File.extname(sarif_file).empty?
  rescue StandardError => e
    puts "Error checking file type: #{e.message}"
    false
  end

  def initialize(sarif_file, destination_path, source_root = nil)
    # Check for directory traversal in the file path and raise an error if found.
    if !destination_path.nil? && !(file_type_check(sarif_file) || File.directory?(sarif_file))
      raise 'The input path must be either a SARIF file or a directory containing SARIF files'
    end

    @sarif_spec = sarif_file
    @dest_path = destination_path
    @source_root = source_root

    # Ensure that we are processing only supported files (e.g., .sarif or directory)

    @severities = %w[error warning note]
    @content = []
    @scan_date = Time.now
    @tools = []
  end

  def generate
    @sarif_reports = load_sarifs(@sarif_spec)
    @results = extract_results

    @sarif_reports.each do |report|
      tool_name = report.runs.first.tool.driver.name
      @tools << tool_name
    end

    # Build graph analysis
    @graph_analyzer = GraphAnalyzer.new
    @graph_analyzer.analyze(@results, source_root: @source_root)

    self
  end

  def load_sarifs(path)
    if File.directory?(path)
      Dir.glob("#{path}/*.sarif").map do |sarif|
        puts "Reading #{sarif}"
        Sarif.load(sarif)
      end
    else
      puts "Reading #{path}"
      [Sarif.load(path)]
    end
  end

  # CodeQL ships its rules in tool extensions (packs) rather than on the driver.
  def severity_from_extensions(extensions, rule_id)
    extensions.each do |extension|
      extension.rules.each do |rule|
        return rule.default_configuration.level if rule.id == rule_id
      end
    end
    nil
  end

  def severity_from_rules(rules, rule_id)
    rules.find { |rule| rule.id == rule_id }&.default_configuration&.level
  end

  # A result may carry its own level, or defer to the level configured on its rule.
  def find_severity(result, run)
    rule_id = result.rule_id
    tool = run.tool
    driver = tool.driver

    return result.level if result.respond_to?(:level)
    return severity_from_extensions(tool.extensions, rule_id) if tool.extensions
    return severity_from_rules(driver.rules, rule_id) if driver.rules&.length&.positive?

    raise "can't work out where to find rules for #{rule_id}, #{tool}, #{driver}"
  end

  # Most tools report a file and a line. Some report a thing that has no file at all -
  # git-branch-audit points at a branch or a commit - and SARIF models those as a
  # logicalLocation with no physicalLocation. Fall back to the logical name so those
  # findings still render, and report the kind so callers can tell a path they can link
  # to from a name they cannot.
  def locate(result)
    location = result.locations&.first
    physical = location&.physical_location
    return physical_location_of(physical) if physical

    logical_location_of(location&.logical_locations&.first)
  end

  def physical_location_of(physical)
    region = physical.region
    { label: physical.artifact_location.uri, linenum: region ? region.start_line : 0, kind: 'file' }
  end

  def logical_location_of(logical)
    { label: logical&.fully_qualified_name || logical&.name || '(no location)',
      linenum: 0,
      kind: logical&.kind || 'other' }
  end

  def format_result(result, report)
    run = report.runs.first
    where = locate(result)

    OpenStruct.new(severity: find_severity(result, run),
                   description: CGI.escapeHTML(result.message.text),
                   **where_fields(where),
                   rule_id: GraphAnalyzer.clean_rule_id(result.rule_id),
                   tool: run.tool.driver.name)
  end

  # The location half of a template row: where the finding is, and whether that is
  # something an editor can be pointed at.
  def where_fields(where)
    { linenum: where[:linenum],
      file_url: where[:label],
      location_kind: where[:kind],
      linkable: where[:kind] == 'file' }
  end

  def extract_results
    output = []
    @sarif_reports.each do |report|
      results = report.runs[0].results
      next if results.nil?

      output += results.map do |result|
        format_result(result, report)
      end
    end
    output
  end

  def results_matching(severity, rule_id)
    @results.select do |result|
      _description = result.description
      result.severity == severity && result.rule_id == rule_id
    end
  end

  # One description per rule id, used as the heading for the group. Where the findings
  # under a rule carry different messages - a branch audit names a different branch and
  # different commits each time - the heading can only show one of them, so the template
  # prints each finding's own message beside its own location as well.
  def rules_and_descriptions(severity)
    @results.select { |e| e.severity == severity }.map do |result|
      [result.rule_id, result.description]
    end.uniq.to_h
  end

  def get_url_for_browser(file_path, mode, line)
    file_path = "#{Dir.pwd}/#{file_path}" unless file_path.start_with?('/')

    if mode == :vim
      extra_param = line ? "&line=#{line}" : ''
      "mvim://open?url=file://#{file_path}" + extra_param
    elsif mode == :vscode
      "vscode://open?url=file://#{file_path}"
    else
      "file://#{file_path}"
    end
  end

  def command_exists?(command)
    `which  #{command} 2>/dev/null`
    $CHILD_STATUS.success?
  end

  def get_url(url, line)
    if command_exists?('mvim')
      get_url_for_browser(url, :vim, line)
    elsif command_exists?('code')
      get_url_for_browser(url, :vscode, line)
    else
      get_url_for_browser(url, nil, nil)
    end
  end

  def publish
    # generate erb template and write to the file from destination_path
    File.open(@dest_path, 'w+') do |file|
      html = ERB.new(self.class.template).result(binding)
      file.write(html)
    end
  end

  def self.template
    File.read("#{File.dirname(__FILE__)}/template.erb")
  end
end

if __FILE__ == $PROGRAM_NAME && !defined?(RSpec)
  # The script is being run directly and not via RSpec
  HtmlReport.new(ARGV[0], ARGV[1], ARGV[2]).generate.publish
end
