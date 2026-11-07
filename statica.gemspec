# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'statica'
  spec.version       = "1.3.0"
  spec.authors       = ['simpsonjulian']
  spec.email         = ['simpsonjulian@gmail.com']

  spec.summary       = 'Static Application Security Testing (SAST) tool for macOS and Linux'
  spec.description   = 'Statica runs multiple security analysis tools and generates unified reports ' \
                       'in console or HTML format. Designed for situations where code cannot be compiled.'
  spec.homepage      = 'https://github.com/simpsonjulian/statica'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir[
    'README.md',
    'LICENSE',
    'statica',
    'csv2sarif',
    'graph_analyzer.rb',
    'statica_sarif.rb',
    'statica_scc.rb',
    'html_report.rb',
    'template.erb',
    'tools.d/*'
  ]

  # stdlib gems no longer shipped as default gems (csv: Ruby 3.4, ostruct: Ruby 4.0).
  # rexml is bundled rather than default too; nuget-hintpath parses .csproj with it and
  # today only gets it transitively through rgl.
  spec.add_dependency 'csv', '~> 3.3'
  spec.add_dependency 'ostruct', '~> 0.6'
  spec.add_dependency 'rexml', '~> 3.2'

  # Required at runtime by the scanners and the HTML report. Homebrew's formula
  # installs the built .gem, which only pulls in gemspec dependencies, so these
  # must live here rather than only in the Gemfile.
  spec.add_dependency 'rgl', '~> 0.6'
  spec.add_dependency 'rubyzip', '~> 2.3'
  spec.add_dependency 'sarif-ruby', '~> 0.1.0'

  spec.bindir        = '.'
  spec.executables   = %w[statica csv2sarif]
  spec.require_paths = ['.']
end
