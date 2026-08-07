# frozen_string_literal: true

require 'spec_helper'
require_relative '../graph_analyzer'
require 'ostruct'
require 'json'

RSpec.describe GraphAnalyzer do
  let(:analyzer) { GraphAnalyzer.new }

  let(:sample_results) do
    [
      OpenStruct.new(
        tool: 'semgrep',
        rule_id: 'sql-injection',
        file_url: 'src/database.rb',
        severity: 'error',
        description: 'Potential SQL injection',
        linenum: 42
      ),
      OpenStruct.new(
        tool: 'semgrep',
        rule_id: 'sql-injection',
        file_url: 'src/models/user.rb',
        severity: 'error',
        description: 'Potential SQL injection',
        linenum: 15
      ),
      OpenStruct.new(
        tool: 'semgrep',
        rule_id: 'sql-injection',
        file_url: 'src/models/post.rb',
        severity: 'error',
        description: 'Potential SQL injection',
        linenum: 23
      ),
      OpenStruct.new(
        tool: 'bearer',
        rule_id: 'hardcoded-secret',
        file_url: 'src/config.rb',
        severity: 'warning',
        description: 'Hardcoded API key',
        linenum: 10
      ),
      OpenStruct.new(
        tool: 'semgrep',
        rule_id: 'xss-vulnerability',
        file_url: 'src/database.rb',
        severity: 'error',
        description: 'Cross-site scripting',
        linenum: 55
      ),
      OpenStruct.new(
        tool: 'bearer',
        rule_id: 'insecure-http',
        file_url: 'src/database.rb',
        severity: 'note',
        description: 'Using HTTP instead of HTTPS',
        linenum: 12
      ),
      OpenStruct.new(
        tool: 'semgrep',
        rule_id: 'insecure-http',
        file_url: 'src/api.rb',
        severity: 'note',
        description: 'Using HTTP instead of HTTPS',
        linenum: 8
      )
    ]
  end

  describe '#initialize' do
    it 'creates an empty graph' do
      expect(analyzer.graph).to be_a(RGL::DirectedAdjacencyGraph)
      expect(analyzer.graph.vertices.size).to eq(0)
    end
  end

  describe '#analyze' do
    before do
      analyzer.analyze(sample_results)
    end

    it 'builds a graph from results' do
      expect(analyzer.graph.vertices.size).to be > 0
    end

    it 'creates analysis nodes for each tool' do
      analysis_nodes = analyzer.node_types.select { |_, type| type == 'analysis' }.keys
      expect(analysis_nodes).to include('analysis:semgrep')
      expect(analysis_nodes).to include('analysis:bearer')
    end

    it 'creates finding nodes' do
      finding_nodes = analyzer.node_types.select { |_, type| type == 'finding' }.keys
      expect(finding_nodes.size).to eq(sample_results.size)
    end

    it 'creates file nodes' do
      file_nodes = analyzer.node_types.select { |_, type| type == 'file' }.keys
      expect(file_nodes).to include('file:src/database.rb')
      expect(file_nodes).to include('file:src/models/user.rb')
    end

    it 'creates HAS edges from analysis to findings' do
      has_edges = analyzer.edge_types.select { |_, type| type == 'HAS' }
      expect(has_edges.size).to eq(sample_results.size)
    end

    it 'creates IN edges from findings to files' do
      in_edges = analyzer.edge_types.select { |_, type| type == 'IN' }
      expect(in_edges.size).to eq(sample_results.size)
    end

    it 'stores finding details' do
      expect(analyzer.finding_details.size).to eq(sample_results.size)

      first_finding = analyzer.finding_details.values.first
      expect(first_finding).to have_key(:rule_id)
      expect(first_finding).to have_key(:severity)
      expect(first_finding).to have_key(:description)
    end
  end

  describe '#analyze with heterogeneous path formats from different tools' do
    let(:source_root) { '/Users/jsimpson/dev/simpsonjulian/statica' }

    # All three results point at the same file in the same scanned codebase, but
    # each string is shaped the way that tool actually emits it (verified against
    # real tool output run against an absolute source path):
    #   - churn (git-derived) always emits a clean, root-relative path
    #   - checkov emits an absolute path with only the leading "/" stripped
    #   - trivy emits a file:// URI resolved against its own uriBaseId
    let(:heterogeneous_results) do
      [
        OpenStruct.new(
          tool: 'churn',
          rule_id: 'top-file-churns',
          file_url: 'Dockerfile',
          severity: 'note',
          description: 'File has been committed to frequently.',
          linenum: 0
        ),
        OpenStruct.new(
          tool: 'checkov',
          rule_id: 'CKV_DOCKER_2',
          file_url: 'Users/jsimpson/dev/simpsonjulian/statica/Dockerfile',
          severity: 'error',
          description: 'Ensure that HEALTHCHECK instructions have been added',
          linenum: 1
        ),
        OpenStruct.new(
          tool: 'trivy',
          rule_id: 'secret',
          file_url: 'file:///Users/jsimpson/dev/simpsonjulian/statica/Dockerfile',
          severity: 'error',
          description: 'Secret found',
          linenum: 3
        )
      ]
    end

    it 'treats the same file reported by different tools as a single file node' do
      analyzer.analyze(heterogeneous_results, source_root: source_root)

      file_nodes = analyzer.node_types.select { |_, type| type == 'file' }.keys
      expect(file_nodes).to eq(['file:Dockerfile'])
    end

    it 'lets a file corroborated by 3 tools clear the densely-connected threshold' do
      analyzer.analyze(heterogeneous_results, source_root: source_root)

      subgraph = analyzer.densely_connected_subgraph(3)
      expect(subgraph[:nodes]).to include('file:Dockerfile')
    end
  end

  describe '#densely_connected_subgraph' do
    before do
      analyzer.analyze(sample_results)
    end

    it 'returns nodes and edges' do
      subgraph = analyzer.densely_connected_subgraph(2)

      expect(subgraph).to have_key(:nodes)
      expect(subgraph).to have_key(:edges)
    end

    it 'includes files with multiple findings' do
      subgraph = analyzer.densely_connected_subgraph(2)

      # src/database.rb has 3 findings, should be included
      expect(subgraph[:nodes]).to include('file:src/database.rb')
    end

    it 'excludes files below threshold' do
      subgraph = analyzer.densely_connected_subgraph(3)

      # Files with < 3 findings should be excluded
      expect(subgraph[:nodes]).not_to include('file:src/config.rb')
    end
  end

  describe '#to_visjs_json' do
    before do
      analyzer.analyze(sample_results)
    end

    it 'returns valid JSON' do
      json = analyzer.to_visjs_json(2)

      expect { JSON.parse(json) }.not_to raise_error
    end

    it 'includes nodes and edges arrays' do
      data = JSON.parse(analyzer.to_visjs_json(2))

      expect(data).to have_key('nodes')
      expect(data).to have_key('edges')
      expect(data['nodes']).to be_an(Array)
      expect(data['edges']).to be_an(Array)
    end

    it 'assigns colors based on node types' do
      data = JSON.parse(analyzer.to_visjs_json(2))

      analysis_node = data['nodes'].find { |n| n['shape'] == 'box' }
      finding_node = data['nodes'].find { |n| n['shape'] == 'ellipse' }
      file_node = data['nodes'].find { |n| n['shape'] == 'ellipse' }

      expect(analysis_node).not_to be_nil
      expect(finding_node).not_to be_nil
      expect(file_node).not_to be_nil
    end

    it 'assigns severity colors to findings' do
      data = JSON.parse(analyzer.to_visjs_json(2))

      error_finding = data['nodes'].find do |n|
        n['shape'] == 'ellipse' && n['color'] == '#e74c3c'
      end

      expect(error_finding).not_to be_nil
    end

    it 'includes edge labels' do
      data = JSON.parse(analyzer.to_visjs_json(2))

      edge = data['edges'].first
      expect(edge).to have_key('label')
      expect(%w[HAS IN]).to include(edge['label'])
    end
  end

  describe 'findings with no file' do
    let(:ref_scoped) do
      OpenStruct.new(
        tool: 'topology',
        rule_id: 'branch-never-merged',
        file_url: nil,
        severity: 'error',
        description: 'Branch never merged',
        linenum: 0
      )
    end

    it 'hangs them off their analysis without inventing a file node' do
      analyzer.analyze([ref_scoped])

      expect(analyzer.graph.vertices).to contain_exactly(
        'analysis:topology', 'finding:branch-never-merged:0'
      )
    end

    # A synthetic file node would put a file nobody touched into the hotspot
    # table on the strength of a finding that was never about a file.
    it 'keeps them out of the hotspot counts' do
      analyzer.analyze(sample_results + [ref_scoped])

      file_nodes = analyzer.graph.vertices.select { |v| v.start_with?('file:') }

      expect(file_nodes).not_to include('file:')
      expect(analyzer.densely_connected_subgraph(1)[:nodes]).not_to include('finding:branch-never-merged:7')
    end
  end
end
