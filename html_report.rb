#!/usr/bin/env ruby
#
require 'json'
require 'ostruct'
require 'erb'

class SarifFile
  def initialize(path)
    @report = get_sarifs(path)
  end

  def results
    output = []
    @report.each do |report|
      output += report.runs[0].results.map { |result| 
                  OpenStruct.new({ severity: result.level,
                                       description: result.message.text,
                                       linenum: result.locations[0].physicalLocation.region.startLine,
                                       file_url: result.locations[0].physicalLocation.artifactLocation.uri,
                                       rule_id: result.ruleId}) }

    end
    output
  end

  private

  def get_sarifs(path)
    if File.directory?(path)
      Dir.glob("#{path}/*.sarif").map { |sarif| JSON.parse(File.read(sarif), object_class: OpenStruct) }
    else
      [JSON.parse(File.read(path), object_class: OpenStruct)]
    end

  end
end

class HtmlReport
  attr_reader :results

  def initialize(sarif_file, destination_path)
    @sarif_spec = sarif_file
    @dest_path = destination_path
    @severities = []
    @content = []
  end

  def generate
    @sarif = SarifFile.new(@sarif_spec)
    @results = @sarif.results
    @severities = @results.map { |result| result.severity }.uniq
    @rule_ids = @results.map { |result| result.rule_id }.uniq
    self
  end

  def publish
    # generate erb template and write to the file from destination_path
    File.open(@dest_path, 'w') do |file|
      file.write(ERB.new(self.class.template).result(binding))
    end
  end

  def self.template
    File.read("#{File.dirname(__FILE__)}/template.erb")
  end
end

if __FILE__ == $0 && !defined?(RSpec)
  # The script is being run directly and not via RSpec
  HtmlReport.new(ARGV[0], ARGV[1]).generate.publish
end