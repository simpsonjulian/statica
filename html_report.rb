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

  def find_severity(result, run)
    rule_id = result.rule_id
    tool = run.tool
    driver = tool.driver

    rules = driver.rules
    if result.respond_to?(:level)
      result.level
    elsif tool.extensions # codeql with packs
      tool.extensions.map do |e|
        e.rules.map do |r|
          return r.default_configuration.level if r.id == rule_id
        end
      end

    elsif rules&.length&.positive? # severity comes from the rule
      rule = rules.select { |r| r.id == rule_id }.first
      rule.default_configuration.level
    else
      raise "can't work out where to find rules for #{rule_id}, #{tool}, #{driver}"
    end
  end

  def format_result(result, report)
    rule_id = result.rule_id
    run = report.runs.first
    severity = find_severity(result, run)

    # Not every finding is file-scoped. A finding about a branch or a ref has
    # nowhere sensible to point in the tree and carries a logicalLocation
    # instead, so every step down to the physicalLocation has to be optional -
    # this used to dereference blind, and one such result took down the whole
    # report rather than just itself.
    location = result.locations&.first
    physical = location&.physical_location
    region = physical&.region
    tool = run.tool.driver.name

    OpenStruct.new({ severity: severity,
                     description: CGI.escapeHTML(result.message.text),
                     linenum: region ? region.start_line : 0,
                     file_url: physical&.artifact_location&.uri,
                     logical_location: location&.logical_locations&.first&.name,
                     rule_id: GraphAnalyzer.clean_rule_id(rule_id),
                     tool: tool })
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

  def command_exists(command)
    `which  #{command} 2>/dev/null`
    $CHILD_STATUS.success?
  end

  def get_url(url, line)
    if command_exists('mvim')
      get_url_for_browser(url, :vim, line)
    elsif command_exists('code')
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
