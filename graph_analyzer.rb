# frozen_string_literal: true

require 'rgl/adjacency'
require 'rgl/traversal'
require 'json'

# Analyzes SARIF results using RGL graph structure
# Graph structure: (analysis)-[:HAS]->(finding)-[:IN]->(file)
class GraphAnalyzer
  attr_reader :graph, :node_types, :edge_types, :finding_details

  def initialize
    @graph = RGL::DirectedAdjacencyGraph.new
    @node_types = {}
    @edge_types = {}
    @finding_details = {}
  end

  def add_node(node, type, _label)
    @graph.add_vertex(node)
    @node_types[node] = type
  end

  def add_edge(from, to, edge_type)
    @graph.add_edge(from, to)
    @edge_types[[from, to]] = edge_type
  end

  # Most findings sit in a file, but some sit on a branch or a commit and have no file
  # at all. Namespacing the node by what it actually is keeps a branch from being
  # counted, coloured or linked as though it were a source file. Returns [node, label].
  def location_node_for(result, source_root)
    kind = result.location_kind || 'file'
    label = kind == 'file' ? self.class.normalize_file_url(result.file_url, source_root) : result.file_url

    ["#{kind}:#{label}", kind, label]
  end

  # One finding as (analysis)-[:HAS]->(finding)-[:IN]->(location), plus the detail the
  # rendered graph shows when you hover it.
  def record_finding(result, finding_node, location_node, kind, label)
    analysis_node = "analysis:#{result.tool}"

    add_node(analysis_node, 'analysis', result.tool)
    add_node(finding_node, 'finding', result.rule_id)
    add_node(location_node, kind, label)
    add_edge(analysis_node, finding_node, 'HAS')
    add_edge(finding_node, location_node, 'IN')

    @finding_details[finding_node] = {
      rule_id: result.rule_id,
      severity: result.severity,
      description: result.description,
      linenum: result.linenum,
      tool: result.tool,
      file: label
    }
  end

  def analyze(results, source_root: nil)
    results.each_with_index do |result, idx|
      finding_node = "finding:#{result.rule_id}:#{idx}"
      location_node, kind, label = location_node_for(result, source_root)
      record_finding(result, finding_node, location_node, kind, label)
    end

    self
  end

  # Different tools report the same file under different shapes depending on how the
  # scan root was invoked (bare relative path, absolute path with the leading "/"
  # stripped, or a file:// URI). Since every result in one analyze() call comes from
  # scanning the same source_root, strip it off wherever it appears so the same file
  # always maps to the same file: node regardless of which tool reported it.
  def self.normalize_file_url(file_url, source_root)
    return file_url if source_root.nil? || source_root.to_s.empty?

    normalized_root = source_root.to_s.chomp('/').delete_prefix('/')

    file_url
      .delete_prefix('file://')
      .delete_prefix('/')
      .delete_prefix("#{normalized_root}/")
  end

  # Locations carrying at least min_connections findings - the ones worth drawing.
  def dense_locations(min_connections)
    counts = Hash.new(0)
    @graph.each_edge { |from, to| counts[to] += 1 if @edge_types[[from, to]] == 'IN' }
    counts.select { |_, count| count >= min_connections }.keys
  end

  # The analysis node that produced a finding, so the drawn subgraph stays connected
  # back to the tool that reported it.
  def collect_analysis_edges(finding_node, nodes, edges)
    @graph.each_edge do |analysis, finding|
      next unless finding == finding_node && @edge_types[[analysis, finding]] == 'HAS'

      nodes.add(analysis)
      edges << [analysis, finding]
    end
  end

  # Every finding reported against one location, plus the analyses that found them.
  def collect_location_edges(location_node, nodes, edges)
    @graph.each_edge do |from, to|
      next unless to == location_node && @edge_types[[from, to]] == 'IN'

      nodes.add(from)
      edges << [from, to]
      collect_analysis_edges(from, nodes, edges)
    end
  end

  def densely_connected_subgraph(min_connections = 3)
    nodes = Set.new
    edges = []

    dense_locations(min_connections).each do |location_node|
      nodes.add(location_node)
      collect_location_edges(location_node, nodes, edges)
    end

    { nodes: nodes.to_a, edges: edges }
  end

  def calculate_file_tool_counts(nodes)
    file_tool_counts = Hash.new(0)

    nodes.each do |node|
      next unless @node_types[node] == 'file'

      # Count unique tools that have findings on this file
      tools = Set.new
      @finding_details.each_value do |details|
        tools.add(details[:tool]) if details[:file] == node.sub('file:', '')
      end

      file_tool_counts[node] = tools.size
    end

    file_tool_counts
  end

  SEVERITY_COLOURS = { 'error' => '#e74c3c', 'warning' => '#f39c12' }.freeze
  DEFAULT_SEVERITY_COLOUR = '#3498db'

  # Just the readable part of a node id: the rule name without the temp-directory
  # prefix a tool may have baked into it, or the filename without its path.
  def node_label(node, type)
    raw_label = node.split(':')[1..].join(':')

    case type
    when 'finding' then GraphAnalyzer.clean_rule_id(raw_label)
    when 'file' then raw_label.split('/').last
    else raw_label
    end
  end

  # [colour, shape, mass, value]. Mass and value decide how strongly vis.js pulls a node
  # towards the centre, so a file flagged by several tools sits where the eye lands.
  FIXED_STYLES = { 'analysis' => ['#97C2FC', 'box', 2, 10] }.freeze
  FALLBACK_STYLE = ['#CCCCCC', 'dot', 1, 5].freeze

  def node_style(node, type, tool_count)
    return FIXED_STYLES[type] if FIXED_STYLES.key?(type)
    return [severity_colour(node), 'ellipse', 1, 5] if type == 'finding'
    return ['#7BE141', 'ellipse', tool_count * 3, 10 + (tool_count * 5)] if type == 'file'

    FALLBACK_STYLE
  end

  def severity_colour(node)
    SEVERITY_COLOURS.fetch(@finding_details[node]&.dig(:severity), DEFAULT_SEVERITY_COLOUR)
  end

  def visjs_node(node, file_tool_counts)
    type = @node_types[node]
    tool_count = type == 'file' ? (file_tool_counts[node] || 1) : nil
    colour, shape, mass, value = node_style(node, type, tool_count)

    { id: node,
      label: node_label(node, type),
      color: colour,
      shape: shape,
      title: tool_count && tool_count > 1 ? "#{type} (#{tool_count} tools)" : type,
      mass: mass,
      value: value }
  end

  def to_visjs_json(min_connections = 3)
    subgraph = densely_connected_subgraph(min_connections)

    # Calculate tool count per file for positioning
    file_tool_counts = calculate_file_tool_counts(subgraph[:nodes])

    nodes = subgraph[:nodes].map { |node| visjs_node(node, file_tool_counts) }

    edges = subgraph[:edges].map do |from, to|
      {
        from: from,
        to: to,
        label: @edge_types[[from, to]],
        arrows: 'to'
      }
    end

    { nodes: nodes, edges: edges }.to_json
  end

  def self.clean_rule_id(rule_id)
    # Remove temp directory paths from rule IDs
    # Example: "var.folders.w2...tmp.XXX.community.rule.name" -> "community.rule.name"
    return rule_id unless rule_id.include?('tmp.')

    parts = rule_id.split('.')
    # Find where the actual rule starts (after tmp.XXX)
    tmp_idx = parts.index { |p| p.start_with?('tmp') }
    if tmp_idx && tmp_idx + 2 < parts.length
      parts[(tmp_idx + 2)..].join('.')
    else
      # Fallback: take last 4 parts
      parts.last(4).join('.')
    end
  end
end
