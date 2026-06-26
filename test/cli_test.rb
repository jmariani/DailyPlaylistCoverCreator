# frozen_string_literal: true

require "minitest/autorun"
require "base64"
require "json"
require "sqlite3"
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
        assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
        assert File.exist?(expected_destination_file(destination_folder, image_file))
        refute File.exist?(image_file)
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
        assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
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
        assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
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

  def test_spotify_login_authorizes_and_exits
    spotify_auth = FakeSpotifyAuth.new

    result = run_cli(["--spotify-login"], spotify_auth:)

    assert_equal 0, result[:status]
    assert_equal 1, spotify_auth.logins
    assert_includes result[:stdout], "[progress] Starting Spotify OAuth login."
    assert_includes result[:stdout], "Spotify login complete."
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
      assert Dir.exist?(expected_title_folder(destination_folder))
      assert_includes result[:stdout], "[progress] Destination folder does not exist; creating:"
      assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
    ensure
      FileUtils.rm_rf(destination_folder) if destination_folder
    end
  end

  def test_creates_title_folder_under_destination
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE])

        assert_equal 0, result[:status]
        assert Dir.exist?(expected_title_folder(destination_folder))
        assert_includes result[:stdout], "[progress] Using title destination folder: #{expected_title_folder(destination_folder)}"
        assert_includes result[:stdout], "Destination folder: #{expected_title_folder(destination_folder)}"
      end
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
        assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
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
        assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
        assert File.exist?(expected_destination_file(destination_folder, image_file))
        assert_empty result[:stderr]
      end
    end
  end

  def test_uses_file_parameter_as_source_file
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder, "chosen.png")

        result = run_cli(["-f", image_file, "-d", destination_folder, "-t", TITLE])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Source file: #{image_file}"
        refute_includes result[:stdout], "Enter source folder:"
        refute_includes result[:stdout], "[progress] Scanning folder:"
        assert_includes result[:stdout], "Moved image: #{File.join(expected_title_folder(destination_folder), "chosen.png")}"
        assert File.exist?(File.join(expected_title_folder(destination_folder), "chosen.png"))
      end
    end
  end

  def test_accepts_gif_as_source_file
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder, "chosen.gif")

        result = run_cli(["-f", image_file, "-d", destination_folder, "-t", TITLE])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Source file: #{image_file}"
        assert_includes result[:stdout], "Moved image: #{File.join(expected_title_folder(destination_folder), "chosen.gif")}"
        assert File.exist?(File.join(expected_title_folder(destination_folder), "chosen.gif"))
      end
    end
  end

  def test_uses_database_parameter_to_select_source_file
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_name = "aabb-cover.jpg"
        first_folder = File.join(source_folder, "aa")
        second_folder = File.join(first_folder, "bb")
        FileUtils.mkdir_p(second_folder)
        image_file = create_image_file(second_folder, image_name)
        database_file = create_image_url_database(destination_folder, [image_name])

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE, "-db", database_file])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Selecting random image from database: #{database_file}"
        assert_includes result[:stdout], "[progress] Random database image selected: #{image_name}"
        assert_includes result[:stdout], "[progress] Built source path from database image name: #{image_file}"
        assert_includes result[:stdout], "Database: #{database_file}"
        assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
        assert File.exist?(expected_destination_file(destination_folder, image_file))
      end
    end
  end

  def test_normalizes_database_image_name_before_building_source_path
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_name = "23 - Nrj6iMR.jpg"
        database_image_name = "  nested\\#{image_name}\n"
        second_folder = File.join(source_folder, "23", "_-")
        FileUtils.mkdir_p(second_folder)
        image_file = create_image_file(second_folder, image_name)
        database_file = create_image_url_database(destination_folder, [database_image_name])

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE, "-db", database_file])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Random database image selected: #{database_image_name}"
        assert_includes result[:stdout], "[progress] Built source path from database image name: #{image_file}"
        assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
      end
    end
  end

  def test_rejects_missing_database_file
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE, "-db", File.join(destination_folder, "missing.sqlite3")])

        assert_equal 1, result[:status]
        assert_includes result[:stderr], "Database file does not exist or is not a file"
      end
    end
  end

  def test_selects_another_database_record_when_built_source_file_is_missing
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        missing_image_name = "ccdd-missing.jpg"
        existing_image_name = "eeff-cover.jpg"
        second_folder = File.join(source_folder, "ee", "ff")
        FileUtils.mkdir_p(second_folder)
        image_file = create_image_file(second_folder, existing_image_name)
        database_file = create_image_url_database(destination_folder, [missing_image_name, existing_image_name])

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE, "-db", database_file],
          image_url_database_factory: ->(_path) { FakeImageUrlDatabase.new([missing_image_name, existing_image_name]) }
        )

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Built source path from database image name: #{File.join(source_folder, "cc", "dd", missing_image_name)}"
        assert_includes result[:stdout], "[progress] Database image file was not found or is not supported; selecting another record."
        assert_includes result[:stdout], "[progress] Built source path from database image name: #{image_file}"
        assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
      end
    end
  end

  def test_rejects_database_selection_when_no_records_resolve_to_existing_files
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_name = "ccdd-missing.jpg"
        database_file = create_image_url_database(destination_folder, [image_name])

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE, "-db", database_file])

        assert_equal 1, result[:status]
        assert_includes result[:stdout], "[progress] Database image file was not found or is not supported; selecting another record."
        assert_includes result[:stderr], "No database image records resolved to an existing supported image file"
      end
    end
  end

  def test_imports_playlist_file_to_spotify
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)
        playlist_file = File.join(destination_folder, "Daily Mix.txt")
        File.write(playlist_file, "First Song - Artist\nMissing Song\n")
        spotify_client = FakeSpotifyClient.new(
          name: "Daily Mix",
          url: "https://open.spotify.com/playlist/abc",
          total: 2,
          added: 1,
          missing: ["Missing Song"]
        )

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE, "-p", playlist_file], spotify_client:)

        assert_equal 0, result[:status]
        assert_equal [playlist_file], spotify_client.imported_files
        assert_includes result[:stdout], "[progress] Creating Spotify playlist from: #{playlist_file}"
        assert_includes result[:stdout], "[progress] Spotify playlist created: Daily Mix; added 1/2 tracks."
        assert_includes result[:stdout], "Playlist file: #{playlist_file}"
        assert_includes result[:stdout], "Spotify playlist: Daily Mix"
        assert_includes result[:stdout], "Spotify playlist URL: https://open.spotify.com/playlist/abc"
        assert_includes result[:stdout], "Spotify tracks added: 1/2"
        assert_includes result[:stdout], "Spotify tracks not found: Missing Song"
      end
    end
  end

  def test_rejects_missing_playlist_file
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE, "-p", File.join(destination_folder, "missing.txt")])

        assert_equal 1, result[:status]
        assert_includes result[:stderr], "Playlist file does not exist or is not a file"
      end
    end
  end

  def test_prompts_with_remembered_folder_destination_and_title_when_options_are_missing
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder)
        defaults_store = FakeDefaultsStore.new(
          "source_kind" => "folder",
          "source_folder" => source_folder,
          "destination_folder" => destination_folder,
          "title" => TITLE
        )

        result = run_cli([], stdin: "\n\n\ny\n", defaults_store:)

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Enter source folder [#{source_folder}]:"
        assert_includes result[:stdout], "Enter destination folder [#{destination_folder}]:"
        assert_includes result[:stdout], "Enter title [#{TITLE}]:"
        assert_includes result[:stdout], "[progress] Using remembered value for enter source folder: #{source_folder}"
        assert_includes result[:stdout], "[progress] Using remembered value for enter destination folder: #{destination_folder}"
        assert_includes result[:stdout], "[progress] Using remembered value for enter title: #{TITLE}"
        assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
      end
    end
  end

  def test_prompts_with_remembered_file_when_last_source_was_a_file
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder, "remembered.webp")
        defaults_store = FakeDefaultsStore.new(
          "source_kind" => "file",
          "source_file" => image_file,
          "destination_folder" => destination_folder,
          "title" => TITLE
        )

        result = run_cli([], stdin: "\n\n\ny\n", defaults_store:)

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Enter source file [#{image_file}]:"
        refute_includes result[:stdout], "[progress] Scanning folder:"
        assert_includes result[:stdout], "[progress] Using remembered value for enter source file: #{image_file}"
        assert_includes result[:stdout], "Source file: #{image_file}"
        assert_includes result[:stdout], "Moved image: #{File.join(expected_title_folder(destination_folder), "remembered.webp")}"
      end
    end
  end

  def test_successful_run_remembers_effective_parameter_values
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)
        defaults_store = FakeDefaultsStore.new

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE], defaults_store:)

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Remembering parameter values for future runs."
        assert_equal "folder", defaults_store.saved.fetch(:source_kind)
        assert_equal source_folder, defaults_store.saved.fetch(:source_folder)
        assert_nil defaults_store.saved.fetch(:source_file)
        assert_equal destination_folder, defaults_store.saved.fetch(:destination_folder)
        assert_equal TITLE, defaults_store.saved.fetch(:title)
      end
    end
  end

  def test_rejects_invalid_file_parameter
    Dir.mktmpdir do |destination_folder|
      result = run_cli(["-f", "/path/that/does/not/exist.jpg", "-d", destination_folder, "-t", TITLE])

      assert_equal 1, result[:status]
      assert_includes result[:stderr], "Source file does not exist or is not a supported image file"
    end
  end

  def test_rejects_unsupported_file_parameter
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        file = File.join(source_folder, "notes.txt")
        File.write(file, "not an image")

        result = run_cli(["-f", file, "-d", destination_folder, "-t", TITLE])

        assert_equal 1, result[:status]
        assert_includes result[:stderr], "Source file does not exist or is not a supported image file"
      end
    end
  end

  def test_rejecting_file_parameter_does_not_reselect
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder, "chosen.jpg")

        result = run_cli(["-f", image_file, "-d", destination_folder, "-t", TITLE], stdin: "n\n")

        assert_equal 1, result[:status]
        assert_includes result[:stderr], "Provided source file was rejected."
        assert_equal 1, result[:stdout].scan("Approve this source image? [y/N/q/d]:").length
      end
    end
  end

  def test_quits_when_q_is_entered_at_image_approval
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder, "chosen.jpg")
        defaults_store = FakeDefaultsStore.new
        notifier = FakeNotifier.new

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE],
          stdin: "q\n",
          defaults_store:,
          notifier:
        )

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Approve this source image? [y/N/q/d]:"
        assert_includes result[:stdout], "[progress] Quit requested during image approval."
        assert_includes result[:stdout], "Quitting."
        assert File.exist?(image_file)
        refute File.exist?(expected_destination_file(destination_folder, image_file))
        assert_nil defaults_store.saved
        assert_empty notifier.notifications
      end
    end
  end

  def test_deletes_source_file_when_d_is_entered_at_image_approval_for_file_parameter
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder, "chosen.jpg")
        defaults_store = FakeDefaultsStore.new
        notifier = FakeNotifier.new

        result = run_cli(
          ["-f", image_file, "-d", destination_folder, "-t", TITLE],
          stdin: "d\n",
          defaults_store:,
          notifier:
        )

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Approve this source image? [y/N/q/d]:"
        assert_includes result[:stdout], "[progress] Deleting source image: #{image_file}"
        assert_includes result[:stdout], "Deleted source image. Quitting."
        refute File.exist?(image_file)
        refute File.exist?(expected_destination_file(destination_folder, image_file))
        assert_nil defaults_store.saved
        assert_empty notifier.notifications
      end
    end
  end

  def test_deletes_source_file_and_database_record_when_d_is_entered_for_database_selection
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_name = "aabb-cover.jpg"
        second_image_name = "ccdd-cover.jpg"
        first_folder = File.join(source_folder, "aa", "bb")
        second_folder = File.join(source_folder, "cc", "dd")
        FileUtils.mkdir_p(first_folder)
        FileUtils.mkdir_p(second_folder)
        image_file = create_image_file(first_folder, image_name)
        create_image_file(second_folder, second_image_name)
        database_file = create_image_url_database(destination_folder, [image_name, second_image_name])
        fake_database = FakeImageUrlDatabase.new([image_name, second_image_name])

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE, "-db", database_file],
          stdin: "d\nq\n",
          image_url_database_factory: ->(_path) { fake_database }
        )

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Deleting source image: #{image_file}"
        assert_includes result[:stdout], "[progress] Deleting database image record: #{image_name}"
        refute File.exist?(image_file)
        assert_equal [image_name], fake_database.deleted_image_names
      end
    end
  end

  def test_deletes_database_record_after_approved_database_image_is_moved
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_name = "aabb-cover.jpg"
        image_folder = File.join(source_folder, "aa", "bb")
        FileUtils.mkdir_p(image_folder)
        image_file = create_image_file(image_folder, image_name)
        database_file = create_image_url_database(destination_folder, [image_name])
        fake_database = FakeImageUrlDatabase.new([image_name])

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE, "-db", database_file],
          image_url_database_factory: ->(_path) { fake_database }
        )

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Moving image to:"
        assert_includes result[:stdout], "[progress] Deleting database image record: #{image_name}"
        refute File.exist?(image_file)
        assert File.exist?(expected_destination_file(destination_folder, image_file))
        assert_equal [image_name], fake_database.deleted_image_names
      end
    end
  end

  def test_image_url_database_deletes_image_name
    Dir.mktmpdir do |folder|
      database_file = create_image_url_database(folder, ["first.jpg", "second.jpg"])

      DailyPlaylistCoverCreator::ImageUrlDatabase.new(database_file).delete_image_name("first.jpg")
      database = SQLite3::Database.new(database_file)
      remaining = database.execute("SELECT image_name FROM image_urls ORDER BY image_name").flatten

      assert_equal ["second.jpg"], remaining
    ensure
      database&.close
    end
  end

  def test_source_folder_is_optional_when_file_parameter_is_set
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder, "chosen.webp")

        result = run_cli(["--file", image_file, "--destination-folder", destination_folder, "--title", TITLE])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Source file: #{image_file}"
        refute_includes result[:stdout], "Source folder:"
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
        assert_includes result[:stdout], "[progress] Moving image to:"
        assert_includes result[:stdout], "[progress] Opening source image with the default application."
        assert_includes result[:stdout], "Approve this source image? [y/N/q/d]:"
        assert_includes result[:stdout], "[progress] Source image approved."
        assert_includes result[:stdout], "[progress] Moving image to:"
        assert_includes result[:stdout], "[progress] 16:9 and cover creation stages are disabled; stopping after selected image is stored."
        refute_includes result[:stdout], "[progress] Requesting GPT title for enhanced image."
        refute_includes result[:stdout], "[progress] GPT title received for enhanced image:"
        refute_includes result[:stdout], "[progress] Generating 1:1 album cover with GPT."
        refute_includes result[:stdout], "[progress] Opening album cover image with the default application."
      end
    end
  end

  def test_stops_after_selected_image_is_stored
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder)

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
        assert_includes result[:stdout], "[progress] 16:9 and cover creation stages are disabled; stopping after selected image is stored."
        refute_includes result[:stdout], "Enhanced image:"
        refute_includes result[:stdout], "16:9 image:"
        refute_includes result[:stdout], "Album cover:"
        refute File.exist?(expected_enhanced_file(destination_folder))
      end
    end
  end

  def test_does_not_call_image_enhancer_after_selection
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder)
        image_enhancer = FakeImageEnhancer.new

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE],
          image_enhancer:,
          image_inspector: FakeImageInspector.new(width: 1200, height: 800)
        )
        copied_file = expected_destination_file(destination_folder, image_file)

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Moved image: #{copied_file}"
        assert_empty image_enhancer.enhanced_images
      end
    end
  end

  def test_does_not_generate_album_cover
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)
        image_enhancer = FakeImageEnhancer.new
        image_opener = FakeImageOpener.new

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE],
          image_enhancer:,
          image_opener:,
          image_inspector: FakeImageInspector.new(width: 1200, height: 800)
        )
        album_cover_file = File.join(expected_title_folder(destination_folder), "morning-focus.png")

        assert_equal 0, result[:status]
        refute_includes result[:stdout], "Album cover: #{album_cover_file}"
        assert_empty image_enhancer.enhanced_images
        refute File.exist?(album_cover_file)
        refute_equal album_cover_file, image_opener.opened_paths.last
      end
    end
  end

  def test_does_not_check_landscape_when_stages_are_disabled
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)
        image_enhancer = FakeImageEnhancer.new

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE],
          image_enhancer:,
          image_inspector: FakeImageInspector.new(width: 1200, height: 800)
        )

        assert_equal 0, result[:status]
        refute_includes result[:stdout], "[progress] Base image is landscape; no 16:9 version needed."
        assert_empty image_enhancer.enhanced_images
        refute_includes result[:stdout], "16:9 image:"
      end
    end
  end

  def test_does_not_generate_or_open_16x9_version_when_stages_are_disabled
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)
        image_opener = FakeImageOpener.new
        image_enhancer = FakeImageEnhancer.new

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE],
          image_opener:,
          image_enhancer:,
          image_inspector: FakeImageInspector.new(width: 800, height: 1200)
        )
        landscape_file = File.join(expected_title_folder(destination_folder), "cover-16x9.png")

        assert_equal 0, result[:status]
        refute_includes result[:stdout], "[progress] Base image is not landscape; generating 16:9 version with GPT."
        refute_includes result[:stdout], "[progress] Opening 16:9 image with the default application."
        refute_includes result[:stdout], "16:9 image: #{landscape_file}"
        assert_empty image_enhancer.enhanced_images
        refute_includes image_opener.opened_paths, landscape_file
        refute File.exist?(landscape_file)
      end
    end
  end

  def test_does_not_generate_album_cover_when_16x9_stage_is_disabled
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)
        image_enhancer = FakeImageEnhancer.new

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE],
          image_enhancer:,
          image_inspector: FakeImageInspector.new(width: 800, height: 1200)
        )
        album_cover_file = File.join(expected_title_folder(destination_folder), "morning-focus.png")

        assert_equal 0, result[:status]
        refute_includes result[:stdout], "Album cover: #{album_cover_file}"
        assert_empty image_enhancer.enhanced_images
        refute File.exist?(album_cover_file)
      end
    end
  end

  def test_image_inspector_reads_png_dimensions
    Dir.mktmpdir do |folder|
      image_file = File.join(folder, "image.png")
      File.binwrite(image_file, png_header(width: 640, height: 480))

      assert_equal [640, 480], DailyPlaylistCoverCreator::CLI::ImageInspector.new.dimensions(image_file)
    end
  end

  def test_reselects_image_until_source_image_is_approved
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)

        image_opener = FakeImageOpener.new
        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE], stdin: "n\ny\n", image_opener:)

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Source image rejected; choosing another."
        assert_includes result[:stdout], "[progress] Source image approved."
        assert_equal 2, result[:stdout].scan("Approve this source image? [y/N/q/d]:").length
        assert_equal 2, image_opener.opened_paths.length
        assert_equal source_folder, File.dirname(image_opener.opened_paths.first)
        assert image_opener.opened_paths.all? { |path| File.dirname(path) == source_folder }
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
        assert_includes result[:stderr], "Could not open source image automatically"
      end
    end
  end

  def test_rejects_when_image_approval_is_not_provided
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE], stdin: "")

        assert_equal 1, result[:status]
        assert_includes result[:stdout], "Approve this source image? [y/N/q/d]:"
        assert_includes result[:stderr], "Image approval is required."
      end
    end
  end

  def test_moves_image_from_nested_folder
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        nested_folder = File.join(source_folder, "nested")
        Dir.mkdir(nested_folder)
        image_file = create_image_file(nested_folder, "cover.png")

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Selected item is a folder; descending."
        assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
        assert_equal "image data", File.read(expected_destination_file(destination_folder, image_file))
        assert_empty result[:stderr]
      end
    end
  end

  def test_smoke_mode_copies_approved_image_instead_of_moving_it
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder)

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE, "--smoke"])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Smoke mode enabled; copying approved image instead of moving it."
        assert_includes result[:stdout], "[progress] Copying image to:"
        assert_includes result[:stdout], "Copied image: #{expected_destination_file(destination_folder, image_file)}"
        assert File.exist?(image_file)
        assert File.exist?(expected_destination_file(destination_folder, image_file))
      end
    end
  end

  def test_uses_unique_filename_when_original_filename_already_exists
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder)
        FileUtils.mkdir_p(expected_title_folder(destination_folder))
        existing_file = expected_destination_file(destination_folder, image_file)
        File.write(existing_file, "existing")

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE])

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Moved image: #{File.join(expected_title_folder(destination_folder), "cover-2.jpg")}"
        assert_equal "image data", File.read(File.join(expected_title_folder(destination_folder), "cover-2.jpg"))
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

  def test_gpt_steps_are_disabled
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)
        memory_file = File.join(destination_folder, "global-memories.json")
        memory_store = DailyPlaylistCoverCreator::CLI::MemoryStore.new(memory_file)
        memory_store.remember(
          playlist_title: "Yesterday",
          enhanced_title: "Golden Hour",
          copied_file: "/tmp/copied.jpg",
          enhanced_file: "/tmp/golden-hour.png",
          landscape_file: nil,
          album_cover_file: "/tmp/yesterday.png"
        )
        image_enhancer = FakeImageEnhancer.new

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE],
          image_enhancer:,
          memory_store_factory: ->(_destination_folder) { memory_store }
        )

        assert_equal 0, result[:status]
        refute_includes result[:stdout], "[progress] Loaded GPT memories from:"
        assert_empty image_enhancer.enhanced_images
      end
    end
  end

  def test_successful_run_does_not_save_gpt_memory_while_stages_are_disabled
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)

        memory_file = File.join(destination_folder, "global-memories.json")
        memory_store = DailyPlaylistCoverCreator::CLI::MemoryStore.new(memory_file)

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE],
          memory_store_factory: ->(_destination_folder) { memory_store }
        )
        assert_equal 0, result[:status]
        refute_includes result[:stdout], "[progress] Saved GPT memories to:"
        refute File.exist?(memory_file)
      end
    end
  end

  def test_memory_store_defaults_to_global_home_file
    memory_store = DailyPlaylistCoverCreator::CLI::MemoryStore.new

    assert_equal File.join(Dir.home, DailyPlaylistCoverCreator::CLI::MemoryStore::FILE_NAME), memory_store.path
  end

  def test_successful_run_sends_completion_notification
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)
        notifier = FakeNotifier.new

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE], notifier:)

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Sending completion notification."
        assert_equal 1, notifier.notifications.length
        assert_equal "Daily Playlist Cover Creator", notifier.notifications.first.fetch(:title)
        assert_includes notifier.notifications.first.fetch(:message), "Finished #{TITLE}"
        assert_includes notifier.notifications.first.fetch(:message), "cover.jpg"
      end
    end
  end

  private

  def create_image_file(folder, name = "cover.jpg")
    path = File.join(folder, name)
    File.write(path, "image data")
    path
  end

  def create_image_url_database(folder, image_names)
    database_file = File.join(folder, "image-urls.sqlite3")
    database = SQLite3::Database.new(database_file)
    database.execute("CREATE TABLE image_urls (image_name TEXT NOT NULL)")
    image_names.each do |image_name|
      database.execute("INSERT INTO image_urls (image_name) VALUES (?)", [image_name])
    end
    database_file
  ensure
    database&.close
  end

  def expected_destination_file(destination_folder, image_file)
    extension = File.extname(image_file).downcase
    File.join(expected_title_folder(destination_folder), "#{File.basename(image_file, ".*")}#{extension}")
  end

  def expected_title_folder(destination_folder)
    File.join(destination_folder, "morning-focus")
  end

  def expected_enhanced_file(destination_folder, original_name = "cover.jpg")
    File.join(expected_title_folder(destination_folder), "#{File.basename(original_name, ".*")}-enh.png")
  end

  def png_header(width:, height:)
    "\x89PNG\r\n\x1A\n".b + ("\x00".b * 8) + [width, height].pack("N2") + ("\x00".b * 8)
  end

  def tiny_png
    Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
    )
  end

  def run_cli(
    argv,
    stdin: "y\n",
    image_opener: FakeImageOpener.new,
    image_enhancer: FakeImageEnhancer.new,
    image_inspector: FakeImageInspector.new(width: 1200, height: 800),
    notifier: FakeNotifier.new,
    spotify_auth: FakeSpotifyAuth.new,
    spotify_client: FakeSpotifyClient.new,
    defaults_store: FakeDefaultsStore.new,
    memory_store_factory: ->(destination_folder) { DailyPlaylistCoverCreator::CLI::MemoryStore.new(File.join(destination_folder, "test-memories.json")) },
    image_url_database_factory: ->(path) { DailyPlaylistCoverCreator::ImageUrlDatabase.new(path) }
  )
    stdin = StringIO.new(stdin)
    stdout = StringIO.new
    stderr = StringIO.new
    status = DailyPlaylistCoverCreator::CLI.run(
      argv,
      stdin:,
      stdout:,
      stderr:,
      image_opener:,
      image_enhancer:,
      image_inspector:,
      notifier:,
      spotify_auth:,
      spotify_client:,
      defaults_store:,
      memory_store_factory:,
      image_url_database_factory:
    )

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

  class FakeImageEnhancer
    attr_reader :enhanced_images

    def initialize
      @enhanced_images = []
    end

    def enhance(image_file:, output_file:, prompt:, size: :auto)
      @enhanced_images << { image_file:, output_file:, prompt:, size: }
      File.write(output_file, "enhanced image")
      output_file
    end
  end

  class FakeImageInspector
    def initialize(width:, height:)
      @width = width
      @height = height
    end

    def dimensions(_path)
      [@width, @height]
    end
  end

  class FakeNotifier
    attr_reader :notifications

    def initialize
      @notifications = []
    end

    def notify(title:, message:)
      @notifications << { title:, message: }
      true
    end
  end

  class FakeSpotifyClient
    attr_reader :imported_files

    def initialize(name: "Daily Mix", url: nil, total: 0, added: 0, missing: [])
      @result = { name:, url:, total:, added:, missing: }
      @imported_files = []
    end

    def import_playlist(file_path:)
      @imported_files << file_path
      @result
    end
  end

  class FakeSpotifyAuth
    attr_reader :logins

    def initialize
      @logins = 0
    end

    def login
      @logins += 1
      "spotify-access-token"
    end
  end

  class FakeImageUrlDatabase
    attr_reader :deleted_image_names

    def initialize(image_names)
      @image_names = image_names
      @deleted_image_names = []
    end

    def each_random_image_name
      return enum_for(:each_random_image_name) unless block_given?

      @image_names.each do |image_name|
        yield image_name
      end
    end

    def delete_image_name(image_name)
      @deleted_image_names << image_name
    end
  end

  class FakeDefaultsStore
    attr_reader :saved

    def initialize(defaults = {})
      @defaults = defaults
      @saved = nil
    end

    def load
      @defaults
    end

    def save(source_kind:, source_folder:, source_file:, destination_folder:, title:)
      @saved = {
        source_kind:,
        source_folder:,
        source_file:,
        destination_folder:,
        title:
      }
    end
  end
end
