#!/usr/bin/env ruby
# frozen_string_literal: true

require 'English'
require 'json'
require 'ostruct'
require 'erb'
require 'cgi/util'

# loads and represents one of more SARIF files
class SarifFile
  attr_reader :report

  def initialize(path)
    @report = get_sarifs(path)
  end

  def find_severity(result, run)
    rule_id = result.ruleId
    tool = run.tool
    driver = tool.driver

    if result.respond_to?(:level)
      result.level
    elsif tool.extensions # codeql with packs
      tool.extensions.map do |e|
        e.rules.map do |r|
          return r.defaultConfiguration.level if r.id == rule_id
        end
      end

    elsif driver.rules&.length&.positive? # severity in the rule
      rule = driver.rules.select { |r| r.id == rule_id }.first
      rule.defaultConfiguration.level
    else
      raise "can't work out where to find rules"
    end
  end

  def format_result(result, report)
    rule_id = result.ruleId
    region = result.locations[0].physicalLocation.region
    run = report.runs.first

    OpenStruct.new({ severity: find_severity(result, run),
                     description: CGI.escapeHTML(result.message.text),
                     linenum: region ? region.startLine : 0,
                     file_url: result.locations[0].physicalLocation.artifactLocation.uri,
                     rule_id: rule_id,
                     tool: report.runs.first.tool.driver.name })
  end

  def results
    output = []
    @report.each do |report|
      results = report.runs[0].results
      next if results.nil?

      output += results.map do |result|
        format_result(result, report)
      end
    end
    output
  end

  private

  def get_sarifs(path)
    if File.directory?(path)
      Dir.glob("#{path}/*.sarif").map do |sarif|
        puts "Reading #{sarif}"
        JSON.parse(File.read(sarif), object_class: OpenStruct)
      end
    else
      puts "Reading #{path}"
      [JSON.parse(File.read(path), object_class: OpenStruct)]
    end
  end
end

# renders sarif findings into HTML and writes to disk
class HtmlReport
  attr_reader :results, :severities

  def initialize(sarif_file, destination_path)
    @sarif_spec = sarif_file
    @dest_path = destination_path
    @severities = %w[error warning note]
    @content = []
    @scan_date = Time.now
    @tools = []
  end

  def generate
    @sarif = SarifFile.new(@sarif_spec)
    @results = @sarif.results

    @sarif.report.each do |report|
      tool_name = report.runs.first.tool.driver.name
      @tools << tool_name
    end
    self
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
    `which -s #{command}`
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
  HtmlReport.new(ARGV[0], ARGV[1]).generate.publish
end
