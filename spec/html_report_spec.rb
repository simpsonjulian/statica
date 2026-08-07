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
      report = HtmlReport.new('spec/simple.sarif', nil)
      report.generate
      expect(report.results.first.description).to eq '&#39;x&#39; is assigned a value but never used.'
    end

    it 'handles a directory of one or more sarif files' do
      report = HtmlReport.new('spec', nil)
      report.generate
      expect(report.results.first.description.split("\n")[0]).to match 'Usage of hard-coded secret'
    end

    it 'publishes a simple html report' do
      report = HtmlReport.new('spec/simple.sarif', 'simple.html')
      report.generate.publish
      expect(File.read('simple.html')).to match '&#39;x&#39; is assigned a value but never used.'
    end

    it 'publishes a more complicated html report' do
      report = HtmlReport.new('spec/complex.sarif', 'complex.html')
      report.generate.publish
      expect(File.read('complex.html')).to match 'Instance does not have Deletion Protection enabled'
    end

    it 'has helper methods for the template' do
      report = HtmlReport.new('spec/complex.sarif', 'complex.html')
      report.generate
      expect(report.rules_and_descriptions('warning')['AVD-AWS-0077'].split("\n")[0]).to match 'Artifact: https:/github.com/terraform-aws-modules/terraform-aws-rds?ref=v2.0.0/modules/db_instance/main.tf'
    end

    it 'gives you a plain local url' do
      plain_url = HtmlReport.new(nil, nil).get_url_for_browser('/foo/bar', nil, nil)
      expect(plain_url).to eq 'file:///foo/bar'
    end

    it 'gives you a vim url' do
      vim_url = HtmlReport.new(nil, nil).get_url_for_browser('/foo/bar', :vim, 26)
      expect(vim_url).to eq 'mvim://open?url=file:///foo/bar&line=26'
    end

    it 'gives you a vscode url' do
      vscode_url = HtmlReport.new(nil, nil).get_url_for_browser('/foo/bar', :vscode, 26)
      expect(vscode_url).to eq 'vscode://open?url=file:///foo/bar'
    end

    it 'can find a command' do
      expect(HtmlReport.new(nil, nil).command_exists('mkdir')).to eq true
    end

    it 'gives a fully qualified path if needed' do
      url = HtmlReport.new(nil, nil).get_url_for_browser('foo.html', nil, nil)
      expect(url).to start_with 'file:///'
      expect(url).not_to eq 'file://foo.html'
    end

    it 'normalizes file paths reported by different tools against the shared source root' do
      report = HtmlReport.new('spec/fixtures/path_normalization', nil, '/home/project')
      report.generate

      file_nodes = report.graph_analyzer.node_types.select { |_, type| type == 'file' }.keys
      expect(file_nodes).to eq(['file:Dockerfile'])
    end
  end
end

RSpec.describe 'SarifReport' do
  context 'parsing sarif files' do
    report = HtmlReport.new('spec/simple.sarif', nil).generate

    it 'has a severity' do
      expect(report.results.first.severity).to eq 'error'
    end

    it 'has a description' do
      expect(report.results.first.description).to eq '&#39;x&#39; is assigned a value but never used.'
    end

    it 'has a filename' do
      expect(report.results.first.file_url).to eq 'file:///C:/dev/sarif/sarif-tutorials/samples/Introduction/simple-example.js'
    end

    it 'has a line number' do
      expect(report.results.first.linenum).to eq 1
    end

    it 'has a rule ID' do
      expect(report.results.first.rule_id).to eq 'no-unused-vars'
    end

    it 'has a tool name' do
      expect(report.results.first.tool).to eq 'ESLint'
    end

    it 'copes with codeql sarif output' do
      report = HtmlReport.new('spec/webgoat_codeql.sarif', nil).generate
      expect(report.results.first.description).to match(/This data transmitted to the user depends on \[sensitive information\].*/)
      expect(report.results.first.severity).to eq 'warning'
    end

    it 'copes with checkov sarif output' do
      report = HtmlReport.new('spec/checkov.sarif', nil).generate
      expect(report.results.first.description).to match 'Suspicious use of netcat with IP address'
      expect(report.results.first.severity).to eq 'error'
    end

    context 'with findings that are not file-scoped' do
      # Named distinctly because the enclosing context assigns a plain local
      # variable called 'report', which would lexically shadow a let of that name.
      let(:topology_report) { HtmlReport.new('spec/fixtures/logical_location.sarif', nil).generate }

      # This used to raise NoMethodError on the missing physicalLocation, which
      # took down the whole report rather than the one result - every other
      # tool's findings went with it.
      it 'reads a result carrying only a logicalLocation' do
        finding = topology_report.results.first

        expect(finding.file_url).to be_nil
        expect(finding.logical_location).to eq 'origin/release/1.8'
        expect(finding.severity).to eq 'error'
      end

      it 'still reads file-scoped results in the same run' do
        finding = topology_report.results.last

        expect(finding.file_url).to eq 'src/main/java/Payment.java'
        expect(finding.logical_location).to be_nil
      end

      it 'renders them without a dead file link' do
        HtmlReport.new('spec/fixtures/logical_location.sarif', 'logical.html').generate.publish
        html = File.read('logical.html')

        expect(html).to match 'origin/release/1.8'
        expect(html).not_to match 'href="file://.*release/1.8"'
      end
    end
  end
end
