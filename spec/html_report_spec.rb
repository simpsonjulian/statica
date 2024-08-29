# frozen_string_literal: true

require 'rspec'
require_relative '../html_report'
require_relative 'spec_helper'

RSpec.describe 'HtmlReport' do
  before do
    # Do nothing
  end

  after do
    # Do nothing
  end

  context 'running the app' do
    it 'handles a single sarif file' do
      report = HtmlReport.new("spec/simple.sarif", nil)
      report.generate
      expect(report.results.first.description).to eq "'x' is assigned a value but never used."
    end

    it 'handles a directory of one or more sarif files' do
      report = HtmlReport.new("spec", nil)
      report.generate
      expect(report.results.first.description).to eq "Use of uninitialized variable."
    end

    it 'publishes a simple html report' do
      report = HtmlReport.new("spec/simple.sarif", "simple.html")
      report.generate.publish
      expect(File.read("simple.html")).to match "'x' is assigned a value but never used."
    end

    it 'publishes a more complicated html report' do
      report = HtmlReport.new("spec/complex.sarif", "complex.html")
      report.generate.publish
      expect(File.read("complex.html")).to match "Use of uninitialized variable"
    end

  end
end

RSpec.describe 'SarifReport' do
  context 'parsing sarif files' do

    sarif_file = SarifFile.new("spec/simple.sarif")

    it 'has a severity' do
      expect(sarif_file.results.first.severity).to eq "error"
    end

    it 'has a description' do
      expect(sarif_file.results.first.description).to eq "'x' is assigned a value but never used."

    end

    it 'has a filename' do
      expect(sarif_file.results.first.file_url).to eq "file:///C:/dev/sarif/sarif-tutorials/samples/Introduction/simple-example.js"
    end

    it 'has a line number' do
      expect(sarif_file.results.first.linenum).to eq 1
    end
  end

end