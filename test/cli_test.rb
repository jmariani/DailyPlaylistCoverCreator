# frozen_string_literal: true

require "minitest/autorun"
require "base64"
require "json"
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
        assert_includes result[:stdout], "Image enhancement prompt: #{DailyPlaylistCoverCreator::CLI::IMAGE_ENHANCEMENT_PROMPT}"
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
        assert_includes result[:stdout], "Image enhancement prompt: #{DailyPlaylistCoverCreator::CLI::IMAGE_ENHANCEMENT_PROMPT}"
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
        assert_includes result[:stdout], "Image enhancement prompt: #{DailyPlaylistCoverCreator::CLI::IMAGE_ENHANCEMENT_PROMPT}"
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
        assert_includes result[:stdout], "Image enhancement prompt: #{DailyPlaylistCoverCreator::CLI::IMAGE_ENHANCEMENT_PROMPT}"
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
        assert_includes result[:stdout], "Image enhancement prompt: #{DailyPlaylistCoverCreator::CLI::IMAGE_ENHANCEMENT_PROMPT}"
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
        assert_equal 1, result[:stdout].scan("Approve this source image? [y/N]:").length
      end
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
        assert_includes result[:stdout], "Approve this source image? [y/N]:"
        assert_includes result[:stdout], "[progress] Source image approved."
        assert_includes result[:stdout], "[progress] Moving image to:"
        assert_includes result[:stdout], "[progress] Normalizing image for GPT upload:"
        assert_includes result[:stdout], "[progress] Enhancing approved image with GPT."
        refute_includes result[:stdout], "[progress] Requesting GPT title for enhanced image."
        refute_includes result[:stdout], "[progress] GPT title received for enhanced image:"
        assert_includes result[:stdout], "[progress] Opening enhanced image with the default application."
        assert_includes result[:stdout], "[progress] Generating 1:1 album cover with GPT."
        assert_includes result[:stdout], "[progress] Opening album cover image with the default application."
      end
    end
  end

  def test_enhances_approved_image_and_names_it_with_title_parameter
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder)

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE])
        enhanced_file = expected_enhanced_file(destination_folder)

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Moved image: #{expected_destination_file(destination_folder, image_file)}"
        assert_includes result[:stdout], "Enhanced image: #{enhanced_file}"
        assert_equal "enhanced image", File.read(enhanced_file)
      end
    end
  end

  def test_normalizes_approved_copy_before_gpt_enhancement
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        image_file = create_image_file(source_folder)
        image_enhancer = FakeImageEnhancer.new
        image_normalizer = FakeImageNormalizer.new

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE],
          image_enhancer:,
          image_normalizer:
        )
        copied_file = expected_destination_file(destination_folder, image_file)
        normalized_file = File.join(expected_title_folder(destination_folder), "cover-normalized.jpg")

        assert_equal 0, result[:status]
        assert_equal [{ image_file: copied_file, output_file: normalized_file }], image_normalizer.normalized_images
        assert_equal normalized_file, image_enhancer.enhanced_images.first.fetch(:image_file)
      end
    end
  end

  def test_generates_album_cover_from_enhanced_image_when_no_16x9_version_exists
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
        enhanced_file = expected_enhanced_file(destination_folder)
        album_cover_file = File.join(expected_title_folder(destination_folder), "morning-focus.png")

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Album cover: #{album_cover_file}"
        assert_equal enhanced_file, image_enhancer.enhanced_images.last.fetch(:image_file)
        assert_equal album_cover_file, image_enhancer.enhanced_images.last.fetch(:output_file)
        assert_equal "1024x1024", image_enhancer.enhanced_images.last.fetch(:size)
        assert_equal "Create a 1:1 album cover using this image as base. The title color is complementary to the background. Justify the title. The title is #{TITLE}", image_enhancer.enhanced_images.last.fetch(:prompt)
        assert_equal album_cover_file, image_opener.opened_paths.last
        assert_equal "enhanced image", File.read(album_cover_file)
      end
    end
  end

  def test_opens_enhanced_image_after_creating_it
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)
        image_opener = FakeImageOpener.new

        result = run_cli(["-s", source_folder, "-d", destination_folder, "-t", TITLE], image_opener:)
        enhanced_file = expected_enhanced_file(destination_folder)

        assert_equal 0, result[:status]
        assert_includes image_opener.opened_paths, enhanced_file
      end
    end
  end

  def test_does_not_generate_16x9_version_when_enhanced_image_is_landscape
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
        assert_includes result[:stdout], "[progress] Enhanced image is landscape; no 16:9 version needed."
        assert_equal 2, image_enhancer.enhanced_images.length
        refute_includes result[:stdout], "16:9 image:"
      end
    end
  end

  def test_generates_and_opens_16x9_version_when_enhanced_image_is_not_landscape
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
        landscape_file = File.join(expected_title_folder(destination_folder), "cover-enh-16x9.png")

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Enhanced image is not landscape; generating 16:9 version with GPT."
        assert_includes result[:stdout], "[progress] Opening 16:9 image with the default application."
        assert_includes result[:stdout], "16:9 image: #{landscape_file}"
        assert_equal 3, image_enhancer.enhanced_images.length
        assert_equal :auto, image_enhancer.enhanced_images[1].fetch(:size)
        assert_includes image_enhancer.enhanced_images[1].fetch(:prompt), "Generate a 16:9 landscape version."
        assert_includes image_opener.opened_paths, landscape_file
        assert_equal "enhanced image", File.read(landscape_file)
      end
    end
  end

  def test_generates_album_cover_from_16x9_version_when_present
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)
        image_enhancer = FakeImageEnhancer.new

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE],
          image_enhancer:,
          image_inspector: FakeImageInspector.new(width: 800, height: 1200)
        )
        landscape_file = File.join(expected_title_folder(destination_folder), "cover-enh-16x9.png")
        album_cover_file = File.join(expected_title_folder(destination_folder), "morning-focus.png")

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "Album cover: #{album_cover_file}"
        assert_equal 3, image_enhancer.enhanced_images.length
        assert_equal landscape_file, image_enhancer.enhanced_images.last.fetch(:image_file)
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

  def test_sips_image_normalizer_writes_jpeg_output
    Dir.mktmpdir do |folder|
      image_file = File.join(folder, "image.png")
      output_file = File.join(folder, "normalized.jpg")
      File.binwrite(image_file, tiny_png)

      DailyPlaylistCoverCreator::CLI::SipsImageNormalizer.new.normalize(image_file:, output_file:)

      assert File.exist?(output_file)
      assert_equal "\xFF\xD8".b, File.binread(output_file, 2)
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
        assert_equal 2, result[:stdout].scan("Approve this source image? [y/N]:").length
        assert_equal 4, image_opener.opened_paths.length
        assert_equal source_folder, File.dirname(image_opener.opened_paths.first)
        assert image_opener.opened_paths.any? { |path| path.start_with?(expected_title_folder(destination_folder)) }
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
        assert_includes result[:stdout], "Approve this source image? [y/N]:"
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

  def test_gpt_steps_include_memory_context
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
        assert_includes result[:stdout], "[progress] Loaded GPT memories from:"
        assert_includes image_enhancer.enhanced_images.first.fetch(:prompt), "Memory context from previous successful runs"
        assert_includes image_enhancer.enhanced_images.first.fetch(:prompt), "Yesterday"
        assert_includes image_enhancer.enhanced_images.first.fetch(:prompt), "Golden Hour"
      end
    end
  end

  def test_successful_run_saves_memory
    Dir.mktmpdir do |source_folder|
      Dir.mktmpdir do |destination_folder|
        create_image_file(source_folder)

        memory_file = File.join(destination_folder, "global-memories.json")
        memory_store = DailyPlaylistCoverCreator::CLI::MemoryStore.new(memory_file)

        result = run_cli(
          ["-s", source_folder, "-d", destination_folder, "-t", TITLE],
          memory_store_factory: ->(_destination_folder) { memory_store }
        )
        memory = JSON.parse(File.read(memory_file))

        assert_equal 0, result[:status]
        assert_includes result[:stdout], "[progress] Saved GPT memories to:"
        refute File.exist?(File.join(expected_title_folder(destination_folder), DailyPlaylistCoverCreator::CLI::MemoryStore::FILE_NAME))
        assert_equal TITLE, memory.fetch("runs").last.fetch("playlist_title")
        assert_equal TITLE, memory.fetch("runs").last.fetch("enhanced_title")
        assert_equal "morning-focus.png", File.basename(memory.fetch("runs").last.fetch("album_cover_file"))
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
        assert_includes notifier.notifications.first.fetch(:message), "morning-focus.png"
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
    image_normalizer: FakeImageNormalizer.new,
    notifier: FakeNotifier.new,
    spotify_auth: FakeSpotifyAuth.new,
    spotify_client: FakeSpotifyClient.new,
    defaults_store: FakeDefaultsStore.new,
    memory_store_factory: ->(destination_folder) { DailyPlaylistCoverCreator::CLI::MemoryStore.new(File.join(destination_folder, "test-memories.json")) }
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
      image_normalizer:,
      notifier:,
      spotify_auth:,
      spotify_client:,
      defaults_store:,
      memory_store_factory:
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

  class FakeImageNormalizer
    attr_reader :normalized_images

    def initialize
      @normalized_images = []
    end

    def normalize(image_file:, output_file:)
      @normalized_images << { image_file:, output_file: }
      File.write(output_file, "normalized image")
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
