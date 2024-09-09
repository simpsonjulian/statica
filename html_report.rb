#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'ostruct'
require 'erb'
require 'cgi/util'

# loads and represents one of more SARIF files
class SarifFile
  def initialize(path)
    @report = get_sarifs(path)
  end

  def results
    output = []
    @report.each do |report|
      results = report.runs[0].results
      next if results.nil?

      output += results.map do |result|
        region = result.locations[0].physicalLocation.region
        result(region, result)
      end

    end
    output
  end

  private

  def result(region, result)
    OpenStruct.new({ severity: result.level,
                     description: CGI::escapeHTML(result.message.text),
                     linenum: region ? region.startLine : 0,
                     file_url: result.locations[0].physicalLocation.artifactLocation.uri,
                     rule_id: result.ruleId })
  end

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
  attr_reader :results

  def initialize(sarif_file, destination_path)
    @sarif_spec = sarif_file
    @dest_path = destination_path
    @severities = []
    @content = []
    @scan_date = Time.now
  end

  def generate
    @sarif = SarifFile.new(@sarif_spec)
    @results = @sarif.results
    @severities = @results.map(&:severity).uniq
    self
  end

  def severities
    %w[error warning note]
  end

  # jscpd has a single rule, which can spam the result page.
  # should probably fix this in `tools.d/jscpd`
  def cope_with_jscpd(result)
    description = result.description
    rule_id = result.rule_id
    language = nil
    description.match(/Clone detected in (\w+)/) { |m| language = m[1] }
    final_rule_id = rule_id == 'duplication' ? "duplication.#{language}" : rule_id
    [description, final_rule_id]
  end

  def results_matching(severity, rule_id)
    @results.select do |result|
      _description, final_rule_id = cope_with_jscpd(result)
      result.severity == severity && final_rule_id == rule_id
    end
  end

  def rules_and_descriptions(severity)
    @results.select { |e| e.severity == severity }.map do |result|
      description, final_rule_id = cope_with_jscpd(result)

      [final_rule_id, description]
    end.uniq.to_h
  end

  def publish
    # generate erb template and write to the file from destination_path
    File.open(@dest_path, 'w') do |file|
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
