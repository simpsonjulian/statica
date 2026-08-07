# frozen_string_literal: true

require 'fileutils'
require 'open3'

# Builds throwaway repositories with a known topology in a temp dir.
#
# The topology checks are entirely history-shaped, so there is no way to
# exercise them without real commit graphs - stubbing git out would only test
# the stub. Commit dates are settable because severity keys off branch age.
class GitFixture
  attr_reader :path

  def initialize(path)
    @path = path
    @counter = 0
    FileUtils.mkdir_p(path)
    git('init', '-q', '-b', 'main')
    git('config', 'user.email', 'fixture@example.com')
    git('config', 'user.name', 'Fixture')
    git('config', 'commit.gpgsign', 'false')
  end

  def git(*args, env: {})
    out, err, status = Open3.capture3(env, 'git', '-C', @path, *args)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  def commit(message, files: nil, days_ago: 0)
    files ||= { "file#{@counter += 1}.txt" => message }
    files.each do |name, content|
      full = File.join(@path, name)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end
    git('add', '-A')
    git('commit', '-q', '-m', message, env: date_env(days_ago))
    git('rev-parse', 'HEAD').strip
  end

  def create_branch(name)
    git('checkout', '-q', '-b', name)
  end

  def checkout(name)
    git('checkout', '-q', name)
  end

  # resolve: auto-resolves conflicts with -X ours. A merge whose two sides both
  # rewrote the same files is exactly what the overlap check is looking for, and
  # such a merge cannot be recorded at all without resolving it somehow. The
  # strategy chosen does not affect which files each side touched.
  def merge(name, days_ago: 0, message: nil, resolve: false)
    args = ['merge', '--no-ff', '-q']
    args += ['-X', 'ours'] if resolve
    args += ['-m', message || "Merge #{name}", name]
    git(*args, env: date_env(days_ago))
  end

  # What a forge's "Squash and merge" button leaves behind: one commit whose
  # patch is the union of the branch's commits, and no ancestry link.
  def squash_merge(name, days_ago: 0, message: nil)
    git('merge', '--squash', '-q', name)
    git('commit', '-q', '-m', message || "Squashed #{name}", env: date_env(days_ago))
  end

  # What "Rebase and merge" leaves behind: the branch's commits replayed onto
  # the target, so per-commit patch IDs survive but ancestry does not.
  def rebase_merge(name, days_ago: 0)
    base = git('merge-base', 'HEAD', name).strip
    git('rev-list', '--reverse', "#{base}..#{name}").split("\n").each do |rev|
      git('cherry-pick', rev, env: date_env(days_ago))
    end
  end

  def cherry_pick(rev, days_ago: 0)
    git('cherry-pick', rev, env: date_env(days_ago))
  end

  # Mirror local heads into refs/remotes/origin/, which is what the analyser
  # sees in a real clone.
  def publish!
    git('for-each-ref', '--format=%(refname:short) %(objectname)', 'refs/heads/')
      .split("\n").each do |line|
      name, sha = line.split
      git('update-ref', "refs/remotes/origin/#{name}", sha)
    end
  end

  def shallow_clone(dest)
    _out, err, status = Open3.capture3('git', 'clone', '-q', '--depth', '1',
                                       "file://#{@path}", dest)
    raise "shallow clone failed: #{err}" unless status.success?

    dest
  end

  private

  def date_env(days_ago)
    stamp = (Time.now - (days_ago * 86_400)).strftime('%Y-%m-%dT%H:%M:%S')
    { 'GIT_AUTHOR_DATE' => stamp, 'GIT_COMMITTER_DATE' => stamp }
  end
end
