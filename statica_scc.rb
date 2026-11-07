# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'statica_sarif'

module Statica
  # Runs scc's git-history reports (hotspots, coupling) and scopes their paths to the
  # scanned directory, for the scc-hotspots and scc-coupling scanners.
  module Scc
    module_function

    def git(dir, *args)
      out, err, status = Open3.capture3('git', '-C', dir, *args)
      abort "error: git #{args.first} failed: #{err.strip}" unless status.success?

      out
    rescue Errno::ENOENT
      abort 'error: git is not on PATH; install it with `brew install git`'
    end

    def version
      Open3.capture2('scc', '--version').first.strip.delete_prefix('scc version ')
    rescue Errno::ENOENT
      abort 'error: scc is not on PATH; install it with `brew install scc`'
    end

    # scc windows history by commit count, not by date. Translate a git date expression
    # into the number of commits since then, so the window means the same thing on a
    # quiet repository as on a busy one.
    def depth_since(dir, since)
      git(dir, 'rev-list', '--count', "--since=#{since}", 'HEAD').to_i
    end

    def report(dir, flag, depth)
      out, err, status = Open3.capture3('scc', flag, '--format', 'json', '--depth', depth.to_s, '.',
                                        chdir: dir)
      abort "error: scc #{flag} failed: #{err.strip}" unless status.success?

      JSON.parse(out)
    rescue Errno::ENOENT
      abort 'error: scc is not on PATH; install it with `brew install scc`'
    end

    # scc reports paths relative to the repository root even when it is pointed at a
    # subdirectory. Returns the path relative to dir, or nil when it falls outside dir,
    # sits in an excluded tree, or has since been deleted.
    def scoped(dir, prefix, path)
      return nil unless path.start_with?(prefix)

      relative = path.delete_prefix(prefix)
      return nil if relative.split('/').any? { |part| EXCLUDES.include?(part) }
      return nil unless File.exist?(File.join(dir, relative))

      relative
    end

    def prefix(dir)
      git(dir, 'rev-parse', '--show-prefix').strip
    end
  end
end
