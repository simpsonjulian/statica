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

  def analyze(results, source_root: nil)
    results.each_with_index do |result, idx|
      analysis_node = "analysis:#{result.tool}"
      finding_node = "finding:#{result.rule_id}:#{idx}"

      add_node(analysis_node, 'analysis', result.tool)
      add_node(finding_node, 'finding', result.rule_id)
      add_edge(analysis_node, finding_node, 'HAS')

      # A finding scoped to a ref rather than a file has no file node to point
      # at. Hanging it off a synthetic one would inflate that file's finding
      # count and put it in the hotspot table on the strength of a finding that
      # was never about a file, so it stays a leaf under its analysis instead.
      file_url = nil
      if result.file_url
        file_url = self.class.normalize_file_url(result.file_url, source_root)
        file_node = "file:#{file_url}"
        add_node(file_node, 'file', file_url)
        add_edge(finding_node, file_node, 'IN')
      end

      # Store finding details
      @finding_details[finding_node] = {
        rule_id: result.rule_id,
        severity: result.severity,
        description: result.description,
        linenum: result.linenum,
        tool: result.tool,
        file: file_url
      }
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

  def densely_connected_subgraph(min_connections = 3)
    # Find files with multiple findings
    file_finding_counts = Hash.new(0)

    @graph.each_edge do |from, to|
      file_finding_counts[to] += 1 if @edge_types[[from, to]] == 'IN'
    end

    # Select only densely connected nodes
    dense_files = file_finding_counts.select { |_, count| count >= min_connections }.keys

    # Build subgraph with these files and their findings
    nodes = Set.new
    edges = []

    dense_files.each do |file_node|
      nodes.add(file_node)

      @graph.each_edge do |from, to|
        next unless to == file_node && @edge_types[[from, to]] == 'IN'

        nodes.add(from)
        edges << [from, to]

        # Also include the analysis node
        @graph.each_edge do |analysis, finding|
          if finding == from && @edge_types[[analysis, finding]] == 'HAS'
            nodes.add(analysis)
            edges << [analysis, finding]
          end
        end
      end
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

  def to_visjs_json(min_connections = 3)
    subgraph = densely_connected_subgraph(min_connections)

    # Calculate tool count per file for positioning
    file_tool_counts = calculate_file_tool_counts(subgraph[:nodes])

    nodes = subgraph[:nodes].map do |node|
      type = @node_types[node]
      raw_label = node.split(':')[1..].join(':')

      # Clean up labels for better readability
      label = case type
              when 'finding'
                # Extract just the rule name, removing temp paths
                # Handle formats like: "tmp.XXX.community.rule.name" -> "community.rule.name"
                GraphAnalyzer.clean_rule_id(raw_label)
              when 'file'
                # Just show filename, not full path
                raw_label.split('/').last
              else
                raw_label
              end

      # Get tool count for files
      tool_count = type == 'file' ? (file_tool_counts[node] || 1) : nil

      # Determine node styling and properties
      color, shape, mass, value = case type
                                  when 'analysis'
                                    ['#97C2FC', 'box', 2, 10]
                                  when 'finding'
                                    severity = @finding_details[node]&.dig(:severity)
                                    color = case severity
                                            when 'error' then '#e74c3c'
                                            when 'warning' then '#f39c12'
                                            else '#3498db'
                                            end
                                    [color, 'ellipse', 1, 5]
                                  when 'file'
                                    # Files with more tools get higher mass/value (drawn to center)
                                    mass_value = tool_count * 3
                                    size_value = 10 + (tool_count * 5)
                                    ['#7BE141', 'ellipse', mass_value, size_value]
                                  else
                                    ['#CCCCCC', 'dot', 1, 5]
                                  end

      title_text = if tool_count && tool_count > 1
                     "#{type} (#{tool_count} tools)"
                   else
                     type
                   end

      {
        id: node,
        label: label,
        color: color,
        shape: shape,
        title: title_text,
        mass: mass,
        value: value
      }
    end

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
      parts[(tmp_idx + 2)..-1].join('.')
    else
      # Fallback: take last 4 parts
      parts.last(4).join('.')
    end
  end
end
