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
        image_file = create_image_file(source_folder)
        result = run_cli(["--destination-folder", destination_folder, "--title", TITLE], stdin: "#{source_folder}\ny\n")

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Enter source folder:"
        assert_includes result[:stdout], "Source folder: #{source_folder}"
        assert_includes result[:stdout], "Destination folder: #{destination_folder}"
        assert_includes result[:stdout], "Title: #{TITLE}"
        assert_includes result[:stdout], "Image enhancement prompt: enhance. cinematic. keep aspect ratio. do not add text."
        assert_includes result[:stdout], "Copied image: #{expected_destination_file(destination_folder, image_file)}"
        assert File.exist?(expected_destination_file(destination_folder, image_file))
        assert_empty result[:stderr]
      end
    end
  end

  def test_prompts_for_destination_folder_when_option_is_missing
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder)
        result = run_cli(["--source-folder", source_folder, "--title", TITLE], stdin: "#{destination_folder}\ny\n")

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Enter destination folder:"
        assert_includes result[:stdout], "Destination folder: #{destination_folder}"
        assert_includes result[:stdout], "Source folder: #{source_folder}"
        assert_includes result[:stdout], "Title: #{TITLE}"
        assert_includes result[:stdout], "Image enhancement prompt: enhance. cinematic. keep aspect ratio. do not add text."
        assert_includes result[:stdout], "Copied image: #{expected_destination_file(destination_folder, image_file)}"
        assert File.exist?(expected_destination_file(destination_folder, image_file))
        assert_empty result[:stderr]
      end
    end
  end

  def test_prompts_for_title_when_option_is_missing
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder)
        result = run_cli(["--source-folder", source_folder, "--destination-folder", destination_folder], stdin: "#{TITLE}\ny\n")

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Enter title:"
        assert_includes result[:stdout], "Source folder: #{source_folder}"
        assert_includes result[:stdout], "Destination folder: #{destination_folder}"
        assert_includes result[:stdout], "Title: #{TITLE}"
        assert_includes result[:stdout], "Image enhancement prompt: enhance. cinematic. keep aspect ratio. do not add text."
        assert_includes result[:stdout], "Copied image: #{expected_destination_file(destination_folder, image_file)}"
        assert File.exist?(expected_destination_file(destination_folder, image_file))
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

  def test_creates_missing_destination_folder
    Dir.mktmpdir do |source_folder|
      destination_folder = File.join(Dir.tmpdir, "daily-playlist-cover-destination-#{Process.pid}-#{object_id}")
      image_file = create_image_file(source_folder)

      result = run_cli(["--source-folder", source_folder, "--destination-folder", destination_folder, "--title", TITLE])

      assert_equal 0, result[:status]
      assert Dir.exist?(destination_folder)
      assert_includes result[:stdout], "[progress] Destination folder does not exist; creating:"
      assert_includes result[:stdout], "Copied image: #{expected_destination_file(destination_folder, image_file)}"
    ensure
      FileUtils.rm_rf(destination_folder) if destination_folder
    end
  end

  def test_rejects_destination_path_that_exists_as_a_file
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |parent_folder|
        create_image_file(source_folder)
        destination_path = File.join(parent_folder, "not-a-folder")
        File.write(destination_path, "already a file")

        result = run_cli(["--source-folder", source_folder, "--destination-folder", destination_path, "--title", TITLE])

        assert_equal 1, result[:status]
        assert_includes result[:stderr], "Destination path exists but is not a directory"
      end
    end
  end

  def test_accepts_existing_source_and_destination_folders
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder)
        result = run_cli(["--source-folder", source_folder, "--destination-folder", destination_folder, "--title", TITLE])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Source folder: #{source_folder}"
        assert_includes result[:stdout], "Destination folder: #{destination_folder}"
        assert_includes result[:stdout], "Title: #{TITLE}"
        assert_includes result[:stdout], "Image enhancement prompt: enhance. cinematic. keep aspect ratio. do not add text."
        assert_includes result[:stdout], "Copied image: #{expected_destination_file(destination_folder, image_file)}"
        assert File.exist?(expected_destination_file(destination_folder, image_file))
        assert_empty result[:stderr]
      end
    end
  end

  def test_accepts_short_switches
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder)
        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Source folder: #{source_folder}"
        assert_includes result[:stdout], "Destination folder: #{destination_folder}"
        assert_includes result[:stdout], "Title: #{TITLE}"
        assert_includes result[:stdout], "Image enhancement prompt: enhance. cinematic. keep aspect ratio. do not add text."
        assert_includes result[:stdout], "Copied image: #{expected_destination_file(destination_folder, image_file)}"
        assert File.exist?(expected_destination_file(destination_folder, image_file))
        assert_empty result[:stderr]
      end
    end
  end

  def test_prints_progress_while_running
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE])

        assert_equal 0, result[:status]
        assert_match(/\A\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[progress\]/, result[:stdout])
        assert_includes result[:stdout], "[progress] Starting daily playlist cover creator."
        assert_includes result[:stdout], "[progress] Inputs validated."
        assert_includes result[:stdout], "[progress] Scanning folder: #{source_folder}"
        assert_includes result[:stdout], "[progress] Random item selected:"
        assert_includes result[:stdout], "[progress] Selected image file:"
        assert_includes result[:stdout], "[progress] Copying image to:"
        assert_includes result[:stdout], "[progress] Opening copied image with the default application."
        assert_includes result[:stdout], "Approve this copied image? [y/N]:"
        assert_includes result[:stdout], "[progress] Copied image approved."
      end
    end
  end

  def test_reselects_image_until_copied_image_is_approved
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)

        image_opener = FakeImageOpener.new
        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE], stdin: "n\ny\n", image_opener:)

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Copied image rejected; removing it and choosing another."
        assert_includes result[:stdout], "[progress] Copied image approved."
        assert_equal 2, result[:stdout].scan("Approve this copied image? [y/N]:").length
        assert_equal 2, image_opener.opened_paths.length
        assert image_opener.opened_paths.all? { |path| path.start_with?(destination_folder) }
      end
    end
  end

  def test_warns_when_selected_image_cannot_be_opened
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE],
          image_opener: FakeImageOpener.new(success: false)
        )

        assert_equal 0, result[:status]
        assert_includes result[:stderr], "Could not open copied image automatically"
      end
    end
  end

  def test_rejects_when_image_approval_is_not_provided
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE], stdin: "")

        assert_equal 1, result[:status]
        assert_includes result[:stdout], "Approve this copied image? [y/N]:"
        assert_includes result[:stderr], "Image approval is required."
      end
    end
  end

  def test_copies_image_from_nested_folder
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        nested_folder = File.join(source_folder, "nested")
        Dir.mkdir(nested_folder)
        image_file = create_image_file(nested_folder, "cover.png")

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Selected item is a folder; descending."
        assert_includes result[:stdout], "Copied image: #{expected_destination_file(destination_folder, image_file)}"
        assert_equal "image data", File.read(expected_destination_file(destination_folder, image_file))
        assert_empty result[:stderr]
      end
    end
  end

  def test_uses_unique_filename_when_original_filename_already_exists
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder)
        existing_file = expected_destination_file(destination_folder, image_file)
        File.write(existing_file, "existing")

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Copied image: #{File.join(destination_folder, "cover-2.jpg")}"
        assert_equal "image data", File.read(File.join(destination_folder, "cover-2.jpg"))
      end
    end
  end

  def test_rejects_source_folder_without_image_files
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        File.write(File.join(source_folder, "notes.txt"), "not an image")

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE])

        assert_equal 1, result[:status]
        assert_includes result[:stderr], "No image files found in source folder"
      end
    end
  end

  private

  def create_image_file(folder, name = "cover.jpg")
    path = File.join(folder, name)
    File.write(path, "image data")
    path
  end

  def expected_destination_file(destination_folder, image_file)
    extension = File.extname(image_file).downcase
    File.join(destination_folder, "#{File.basename(image_file, ".*")}#{extension}")
  end

  def run_cli(
    argv,
    stdin: "y\n",
    image_opener: FakeImageOpener.new
  )
    stdin = StringIO.new(stdin)
    stdout = StringIO.new
    stderr = StringIO.new
    status = DailyPlaylistCoverCreator::CLI.run(argv, stdin:, stdout:, stderr:, image_opener:)

    {
      status:,
      stdout: stdout.string,
      stderr: stderr.string
    }
  end

  class FakeImageOpener
    attr_reader :opened_paths

    def initialize(success: true)
      @success = success
      @opened_paths = []
    end

    def open(path)
      @opened_paths << path
      @success
    end
  end
end
