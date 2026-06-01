# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"

require_relative "../lib/daily_playlist_cover_creator/cli"

class CLITest < Minitest::Test
  TITLE = "Morning Focus"

  def test_prompts_for_source_folder_when_option_is_missing
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        result = run_cli(["--destination-folder", destination_folder, "--title", TITLE], stdin: "#{source_folder}\n")

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Enter source folder: Source folder: #{source_folder}"
        assert_includes result[:stdout], "Destination folder: #{destination_folder}"
        assert_includes result[:stdout], "Title: #{TITLE}"
        assert_empty result[:stderr]
      end
    end
  end

  def test_prompts_for_destination_folder_when_option_is_missing
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        result = run_cli(["--source-folder", source_folder, "--title", TITLE], stdin: "#{destination_folder}\n")

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Enter destination folder:"
        assert_includes result[:stdout], "Destination folder: #{destination_folder}"
        assert_includes result[:stdout], "Source folder: #{source_folder}"
        assert_includes result[:stdout], "Title: #{TITLE}"
        assert_empty result[:stderr]
      end
    end
  end

  def test_prompts_for_title_when_option_is_missing
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        result = run_cli(["--source-folder", source_folder, "--destination-folder", destination_folder], stdin: "#{TITLE}\n")

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Enter title:"
        assert_includes result[:stdout], "Source folder: #{source_folder}"
        assert_includes result[:stdout], "Destination folder: #{destination_folder}"
        assert_includes result[:stdout], "Title: #{TITLE}"
        assert_empty result[:stderr]
      end
    end
  end

  def test_rejects_blank_prompted_source_folder
    Dir.mktmpdir do |destination_folder|
      result = run_cli(["--destination-folder", destination_folder, "--title", TITLE], stdin: "\n")

      assert_equal 1, result[:status]
      assert_includes result[:stdout], "Enter source folder:"
      assert_includes result[:stderr], "Source folder is required."
    end
  end

  def test_rejects_blank_prompted_destination_folder
    Dir.mktmpdir do |source_folder|
      result = run_cli(["--source-folder", source_folder, "--title", TITLE], stdin: "\n")

      assert_equal 1, result[:status]
      assert_includes result[:stdout], "Enter destination folder:"
      assert_includes result[:stderr], "Destination folder is required."
    end
  end

  def test_rejects_blank_prompted_title
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        result = run_cli(["--source-folder", source_folder, "--destination-folder", destination_folder], stdin: "\n")

        assert_equal 1, result[:status]
        assert_includes result[:stdout], "Enter title:"
        assert_includes result[:stderr], "Title is required."
      end
    end
  end

  def test_rejects_missing_source_folder
    Dir.mktmpdir do |destination_folder|
      result = run_cli(["--source-folder", "/path/that/does/not/exist", "--destination-folder", destination_folder, "--title", TITLE])

      assert_equal 1, result[:status]
      assert_includes result[:stderr], "Source folder does not exist or is not a directory"
    end
  end

  def test_rejects_missing_destination_folder
    Dir.mktmpdir do |source_folder|
      result = run_cli(["--source-folder", source_folder, "--destination-folder", "/path/that/does/not/exist", "--title", TITLE])

      assert_equal 1, result[:status]
      assert_includes result[:stderr], "Destination folder does not exist or is not a directory"
    end
  end

  def test_accepts_existing_source_and_destination_folders
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        result = run_cli(["--source-folder", source_folder, "--destination-folder", destination_folder, "--title", TITLE])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Source folder: #{source_folder}"
        assert_includes result[:stdout], "Destination folder: #{destination_folder}"
        assert_includes result[:stdout], "Title: #{TITLE}"
        assert_empty result[:stderr]
      end
    end
  end

  def test_accepts_short_switches
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Source folder: #{source_folder}"
        assert_includes result[:stdout], "Destination folder: #{destination_folder}"
        assert_includes result[:stdout], "Title: #{TITLE}"
        assert_empty result[:stderr]
      end
    end
  end

  private

  def run_cli(argv, stdin: "")
    stdin = StringIO.new(stdin)
    stdout = StringIO.new
    stderr = StringIO.new
    status = DailyPlaylistCoverCreator::CLI.run(argv, stdin:, stdout:, stderr:)

    {
      status:,
      stdout: stdout.string,
      stderr: stderr.string
    }
  end
end
