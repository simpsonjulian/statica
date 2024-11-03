require_relative 'spec_helper'

class Node
  attr_reader :name, :properties

  def initialize(name, properties)
    @name = name
    @properties = properties
  end

  def id
    __id__
  end
end

class Relationship
  attr_reader :from, :to, :properties

  def initialize(node1, node2, properties = {})
    @from = node1
    @to = node2
    @properties = properties
  end

  def id
    __id__
  end
end

class PropertyDag
  attr_reader :nodes, :relationships

  def initialize
    @nodes = []
    @relationships = []
  end

  def add_node(name, properties)
    @nodes ||= []
    @nodes << Node.new(name, properties)
  end

  def add_relationship(name1, name2, properties = {})
    @relationships ||= []
    node1 = find_nodes(name1)
    node2 = find_nodes(name2)
    @relationships << Relationship.new(node1, node2, properties)
  end

  def find_nodes(name)
    @nodes.select { |node| node.name == name }.first
  end

  def accumulate_relationships_by_node(nodes, relationships1)
    output ||= {}
    nodes.each do |node|
      relationships1.each do |rel|
        if rel.to == node
          output[rel.id] ||= 0
          output[rel.id] += 1
        end
      end
    end
    output
  end

  def find_nodes_by_degree(max)

    nodes = @relationships.map(&:to)

    relationships_in_scope = accumulate_relationships_by_node(nodes, @relationships).select { |k, v| v <= max }

    relationships_in_scope.sort_by { |k, v| v }.reverse

    relationships_in_scope.map do |id, _count|
      ObjectSpace._id2ref(id)
    end
  end

end

RSpec.describe PropertyDag do

  it 'lets you add 2 nodes and a relationship' do
    graph = PropertyDag.new
    graph.add_node('A', { shoe: 'nike' })
    graph.add_node('B', { cheese: 'cheddar' })
    graph.add_relationship('A', 'B')
    expect(graph.nodes.first.properties[:shoe]).to eq 'nike'
    expect(graph.relationships.first.to.properties[:cheese]).to eq 'cheddar'
  end

  it 'has properties on the relationship' do
    graph = PropertyDag.new
    graph.add_node('A', { shoe: 'nike' })
    graph.add_node('B', { cheese: 'cheddar' })
    graph.add_relationship('A', 'B', { hat: 'fedora' })
    expect(graph.relationships.first.properties[:hat]).to eq 'fedora'
  end

  it 'lets you add properties to a name' do
    graph = PropertyDag.new
    graph.add_node('Alice', { age: 30 })
    expect(graph.find_nodes('Alice').name).to eq 'Alice'
  end

  it 'lets you search by number of relationships to a node' do
    graph = PropertyDag.new
    graph.add_node('foo.js', {})
    graph.add_node('bar.js', {})
    graph.add_node('Lizard', {})
    graph.add_node('Checkov', {})
    graph.add_node('Valgrind', {})

    graph.add_relationship('Checkov', 'foo.js')
    graph.add_relationship('Lizard', 'foo.js')
    graph.add_relationship('Checkov', 'bar.js')
    graph.add_relationship('Lizard', 'bar.js')
    graph.add_relationship('Valgrind', 'bar.js')

    graph_find_nodes_by_degree = graph.find_nodes_by_degree(3)
    expect(graph_find_nodes_by_degree.first.to.name).to eq 'foo.js'
    expect(graph_find_nodes_by_degree.last.to.name).to eq 'bar.js'
  end

end