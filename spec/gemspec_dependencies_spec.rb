# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'

# The Homebrew formula installs the built .gem with `gem install`, which only
# brings in the gemspec's runtime dependencies; anything listed only in the
# Gemfile is missing at runtime (statica 1.2.8 shipped this way and every Ruby
# scanner failed with "cannot load such file -- sarif").
#
# This spec requires every library that the packaged Ruby files require, in a
# fresh `ruby --disable-gems` process whose load path holds only the Ruby
# standard library plus the gemspec's runtime dependency closure. Gems that are
# merely installed on this machine, or present in the Gemfile, can't satisfy it.
RSpec.describe 'statica.gemspec runtime dependencies' do
  root = File.expand_path('..', __dir__)
  gemspec = Gem::Specification.load(File.join(root, 'statica.gemspec'))

  ruby_files = gemspec.files.select do |file|
    path = File.join(root, file)
    next false unless File.file?(path)

    file.end_with?('.rb') || File.open(path, &:gets).to_s.match?(/\A#!.*\bruby\b/)
  end

  required_libs = ruby_files.each_with_object(Hash.new { |h, k| h[k] = [] }) do |file, libs|
    File.foreach(File.join(root, file)) do |line|
      lib = line[/^\s*require\s+['"]([^'"]+)['"]/, 1]
      libs[lib] << file if lib
    end
  end

  def runtime_closure(specs, seen = {})
    specs.each do |spec|
      next if seen.key?(spec.name)

      seen[spec.name] = spec
      runtime_closure(spec.runtime_dependencies.map(&:to_spec), seen)
    end
    seen.values
  end

  it 'finds the packaged Ruby files and their requires' do
    expect(ruby_files).to include('statica_sarif.rb', 'html_report.rb', 'csv2sarif')
    expect(required_libs.keys).to include('sarif', 'zip', 'rgl/adjacency')
  end

  it 'can load every required library from the runtime dependencies alone' do
    closure = runtime_closure(gemspec.runtime_dependencies.map(&:to_spec))
    load_path_args = closure.flat_map(&:full_require_paths).flat_map { |dir| ['-I', dir] }

    script = <<~RUBY
      ARGV.each do |lib|
        require lib
      rescue LoadError
        puts lib
      end
    RUBY

    run = lambda do
      Open3.capture3({ 'RUBYOPT' => nil, 'RUBYLIB' => nil },
                     RbConfig.ruby, '--disable-gems', *load_path_args, '-e', script, *required_libs.keys)
    end
    stdout, stderr, status = defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.call

    expect(status).to be_success, stderr
    missing = stdout.split("\n").to_h { |lib| [lib, required_libs[lib]] }
    expect(missing).to be_empty,
                       "not loadable from gemspec runtime dependencies (lib => files): #{missing}"
  end
end
