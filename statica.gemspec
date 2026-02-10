# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'statica'
  spec.version       = '0.1.0'
  spec.authors       = ['simpsonjulian']
  spec.email         = ['simpsonjulian@gmail.com']

  spec.summary       = 'Static Application Security Testing (SAST) tool for macOS and Linux'
  spec.description   = 'Statica runs multiple security analysis tools and generates unified reports in console or HTML format. Designed for situations where code cannot be compiled.'
  spec.homepage      = 'https://github.com/simpsonjulian/statica'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage

  spec.files = Dir[
    'README.md',
    'LICENSE',
    'statica',
    'csv2sarif',
    'graph_analyzer.rb',
    'html_report.rb',
    'template.erb',
    'tools.d/*'
  ]

  spec.bindir        = '.'
  spec.executables   = %w[statica csv2sarif]
  spec.require_paths = ['.']
end
