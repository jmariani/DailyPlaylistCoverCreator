# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"

require_relative "../lib/daily_playlist_cover_creator/cli"

class CLITest < Minitest::Test
  def test_requires_source_folder
    result = run_cli([])

    assert_equal 1, result[:status]
    assert_includes result[:stderr], "Missing required option: --source-folder"
  end

  def test_rejects_missing_source_folder
    result = run_cli(["--source-folder", "/path/that/does/not/exist"])

    assert_equal 1, result[:status]
    assert_includes result[:stderr], "Source folder does not exist or is not a directory"
  end

  def test_accepts_existing_source_folder
    Dir.mktmpdir do |source_folder|
      result = run_cli(["--source-folder", source_folder])

      assert_equal 0, result[:status]
      assert_includes result[:stdout], "Source folder: #{source_folder}"
      assert_empty result[:stderr]
    end
  end

  private

  def run_cli(argv)
    stdout = StringIO.new
    stderr = StringIO.new
    status = DailyPlaylistCoverCreator::CLI.run(argv, stdout:, stderr:)

    {
      status:,
      stdout: stdout.string,
      stderr: stderr.string
    }
  end
end
