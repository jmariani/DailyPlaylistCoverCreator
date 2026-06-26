# frozen_string_literal: true

require "optparse"
require "fileutils"
require "json"
require_relative "gpt_image_enhancer"
require_relative "image_url_database"
require_relative "spotify_client"

module DailyPlaylistCoverCreator
  class CLI
    IMAGE_EXTENSIONS = %w[.gif .jpg .jpeg .png .webp].freeze
    LANDSCAPE_PROMPT = <<~PROMPT.strip
      Enhance the provided image while preserving the original composition, subject placement, artistic style, visual identity, and aspect ratio.

      Create a bright cinematic version with premium-quality detail, balanced contrast, open shadows, rich midtones, clean highlights, enhanced color separation, refined texture detail, and natural dynamic range.

      Increase clarity, depth, sharpness, and visual impact while maintaining a luminous appearance. Preserve detail in both highlights and shadows. Avoid crushed blacks, excessive contrast, heavy vignettes, dark cinematic grading, muddy shadows, or loss of detail.

      Preserve all original elements, colors, shapes, linework, textures, and design motifs. Maintain the original artistic intent and overall mood while improving image quality, readability, depth, and polish.

      Apply subtle atmospheric depth, professional color grading, enhanced micro-contrast, improved edge definition, and gallery-quality rendering.

      For illustrations and artwork:

      * Preserve the original illustration style.
      * Preserve the original color palette and visual language.
      * Enhance line quality, texture fidelity, and print quality.
      * Do not introduce photorealistic elements unless present in the source.

      For photographs:

      * Improve lighting, color balance, local contrast, texture detail, and depth.
      * Maintain a natural appearance.
      * Preserve skin tones and realistic materials.

      Do not:

      * Add new subjects.
      * Remove existing subjects.
      * Add text, captions, logos, signatures, watermarks, borders, or typography.
      * Change the composition.
      * Change the artistic style.
      * Crop important content.
      * Darken the image.
      * Replace the original artwork with a different interpretation.

      Output a high-resolution, professionally enhanced image that remains faithful to the source while appearing significantly cleaner, sharper, richer, brighter, and more cinematic.
      Expand the canvas to a 16:9 widescreen composition while preserving the original image as the central focal point.
      Extend the background, environment, patterns, textures, waves, sky, landscape, or surrounding design elements naturally beyond the original borders. Maintain visual continuity and stylistic consistency.
      Do not crop the original artwork. Do not stretch the image. Do not distort the subject. Generate seamless content that feels like a natural continuation of the original scene.
    PROMPT
    ALBUM_COVER_PROMPT_TEMPLATE = <<~PROMPT.strip
      Create a professional album cover using the provided image as the base artwork.

      Preserve the original subject matter, composition, mood, perspective, and artistic style. Enhance image quality while maintaining visual fidelity to the source.

      Transform the image into a polished album-cover design with:

      * Enhanced contrast and clarity
      * Improved sharpness and texture detail
      * Cinematic lighting and depth
      * Rich color separation and dynamic range
      * Refined highlights and shadow detail
      * Premium print-quality finish
      * Subtle atmospheric depth where appropriate
      * Clean, professional visual hierarchy

      Typography:

      * Remove all existing text, logos, signatures, watermarks, labels, captions, speech bubbles, stickers, and typography from the original image.
      * Add only the album title:
      "[TITLE]"
      * Use a title color complementary to the dominant background colors.
      * Ensure maximum readability and visual balance.
      * Use elegant, modern typography appropriate to the image style.
      * Justify and align the title cleanly within the composition.
      * Keep the title relatively small and understated.
      * Integrate the title naturally into the artwork rather than placing it as a separate overlay.
      * Do not add artist names, subtitles, credits, parental advisory labels, or any additional text.

      Composition:

      * Maintain a clean album-cover aesthetic.
      * Preserve all important visual elements from the source image.
      * Avoid adding new subjects unless necessary for composition.
      * Keep the design visually balanced.
      * No borders or frames unless naturally suited to the artwork.

      Output:

      * Album-cover quality.
      * High resolution.
      * Professional music-release artwork.
      * Square 1:1 format.
      * Only the album title should appear in the final image.
    PROMPT

    def self.run(
      argv,
      stdin: $stdin,
      stdout: $stdout,
      stderr: $stderr,
      image_opener: SystemImageOpener.new,
      image_enhancer: GptImageEnhancer.new,
      image_inspector: ImageInspector.new,
      notifier: SystemNotifier.new,
      spotify_auth: nil,
      spotify_client: nil,
      defaults_store: DefaultsStore.new,
      memory_store_factory: ->(_destination_folder) { MemoryStore.new },
      image_url_database_factory: ->(path) { ImageUrlDatabase.new(path) }
    )
      spotify_auth ||= SpotifyAuth.new(stdout: stdout)
      spotify_client ||= SpotifyClient.new(token_provider: spotify_auth)
      new(
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
      ).run(argv)
    end

    def initialize(stdin:, stdout:, stderr:, image_opener:, image_enhancer:, image_inspector:, notifier:, spotify_auth:, spotify_client:, defaults_store:, memory_store_factory:, image_url_database_factory:)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @image_opener = image_opener
      @image_enhancer = image_enhancer
      @image_inspector = image_inspector
      @notifier = notifier
      @spotify_auth = spotify_auth
      @spotify_client = spotify_client
      @defaults_store = defaults_store
      @memory_store_factory = memory_store_factory
      @image_url_database_factory = image_url_database_factory
    end

    def run(argv)
      progress "Starting daily playlist cover creator."
      options = parse(argv)
      if options[:spotify_login]
        progress "Starting Spotify OAuth login."
        @spotify_auth.login
        @stdout.puts "Spotify login complete."
        return 0
      end

      defaults = @defaults_store.load
      source_folder = options[:source_folder]
      destination_folder = options[:destination_folder]
      title = options[:title]
      source_file = options[:file]
      playlist = options[:playlist]
      smoke = options[:smoke]
      database = options[:database]

      unless source_folder || source_file
        if defaults["source_kind"] == "file" && present?(defaults["source_file"])
          source_file = prompt_for_source_file(defaults["source_file"])
        else
          source_folder = prompt_for_source_folder(defaults["source_folder"])
        end
      end

      unless destination_folder
        destination_folder = prompt_for_destination_folder(defaults["destination_folder"])
      end

      unless title
        title = prompt_for_title(defaults["title"])
      end

      if source_folder.to_s.empty? && source_file.to_s.empty?
        @stderr.puts "Source folder is required."
        return 1
      end

      if destination_folder.empty?
        @stderr.puts "Destination folder is required."
        return 1
      end

      if title.empty?
        @stderr.puts "Title is required."
        return 1
      end

      if source_file && !image_file?(source_file)
        @stderr.puts "Source file does not exist or is not a supported image file: #{source_file}"
        return 1
      end

      if source_folder && !File.directory?(source_folder)
        @stderr.puts "Source folder does not exist or is not a directory: #{source_folder}"
        return 1
      end

      if database && !File.file?(database)
        @stderr.puts "Database file does not exist or is not a file: #{database}"
        return 1
      end

      if playlist && !File.file?(playlist)
        @stderr.puts "Playlist file does not exist or is not a file: #{playlist}"
        return 1
      end

      unless ensure_destination_folder(destination_folder)
        return 1
      end

      progress "Inputs validated."
      spotify_playlist = import_spotify_playlist(playlist)
      destination_root = destination_folder
      destination_folder = prepare_work_destination_folder(destination_folder, title)
      copied_file = select_store_and_approve_image(source_folder, destination_folder, source_file, database, smoke:)
      progress "16:9 and cover creation stages are disabled; stopping after selected image is stored."
      # memory_store = @memory_store_factory.call(destination_folder)
      # memory_context = memory_store.context
      # progress "Loaded GPT memories from: #{memory_store.path}"
      # landscape_file = create_landscape_version_if_needed(copied_file, destination_folder, memory_context)
      # album_cover_file = create_album_cover(copied_file, destination_folder, title, memory_context)
      # memory_store.remember(
      #   playlist_title: title,
      #   enhanced_title: title,
      #   copied_file: copied_file,
      #   enhanced_file: nil,
      #   landscape_file: landscape_file,
      #   album_cover_file: album_cover_file
      # )
      # progress "Saved GPT memories to: #{memory_store.path}"
      remember_defaults(
        source_folder: source_folder,
        source_file: source_file,
        destination_folder: destination_root,
        title: title
      )
      notify_finished(title, copied_file)

      @stdout.puts "Source folder: #{File.expand_path(source_folder)}" if source_folder
      @stdout.puts "Source file: #{File.expand_path(source_file)}" if source_file
      @stdout.puts "Database: #{File.expand_path(database)}" if database
      @stdout.puts "Destination folder: #{File.expand_path(destination_folder)}"
      @stdout.puts "Title: #{title}"
      @stdout.puts "Playlist file: #{File.expand_path(playlist)}" if playlist
      if spotify_playlist
        @stdout.puts "Spotify playlist: #{spotify_playlist.fetch(:name)}"
        @stdout.puts "Spotify playlist URL: #{spotify_playlist.fetch(:url)}" if spotify_playlist.fetch(:url)
        @stdout.puts "Spotify tracks added: #{spotify_playlist.fetch(:added)}/#{spotify_playlist.fetch(:total)}"
        @stdout.puts "Spotify tracks not found: #{spotify_playlist.fetch(:missing).join(", ")}" unless spotify_playlist.fetch(:missing).empty?
      end
      @stdout.puts "#{smoke ? "Copied" : "Moved"} image: #{copied_file}"
      # @stdout.puts "16:9 image: #{landscape_file}" if landscape_file
      # @stdout.puts "Album cover: #{album_cover_file}"
      0
    rescue OptionParser::ParseError => e
      @stderr.puts e.message
      @stderr.puts parser
      1
    rescue EmptySourceFolderError => e
      @stderr.puts e.message
      1
    rescue ImageApprovalRequiredError => e
      @stderr.puts e.message
      1
    rescue QuitRequested
      progress "Quit requested during image approval."
      @stdout.puts "Quitting."
      0
    rescue SourceFileDeleted
      @stdout.puts "Deleted source image. Quitting."
      0
    rescue StandardError => e
      @stderr.puts e.message
      1
    end

    private

    EmptySourceFolderError = Class.new(StandardError)
    ImageApprovalRequiredError = Class.new(StandardError)
    QuitRequested = Class.new(StandardError)
    SourceFileDeleted = Class.new(StandardError)

    def parse(argv)
      options = {}
      parser(options).parse!(normalize_database_option(argv))
      options
    end

    def normalize_database_option(argv)
      argv.map { |argument| %w[-db -database].include?(argument) ? "--database" : argument }
    end

    def prompt_for_source_folder(default_value = nil)
      progress "Source folder was not provided."
      prompt_with_default("Enter source folder", default_value)
    end

    def prompt_for_source_file(default_value = nil)
      progress "Source file was not provided."
      prompt_with_default("Enter source file", default_value)
    end

    def prompt_for_destination_folder(default_value = nil)
      progress "Destination folder was not provided."
      prompt_with_default("Enter destination folder", default_value)
    end

    def prompt_for_title(default_value = nil)
      progress "Title was not provided."
      prompt_with_default("Enter title", default_value)
    end

    def prompt_with_default(label, default_value)
      @stdout.print default_value.to_s.empty? ? "#{label}: " : "#{label} [#{default_value}]: "
      answer = @stdin.gets&.chomp.to_s

      if answer.empty? && present?(default_value)
        progress "Using remembered value for #{label.downcase}: #{default_value}"
        return default_value
      end

      answer
    end

    def remember_defaults(source_folder:, source_file:, destination_folder:, title:)
      progress "Remembering parameter values for future runs."
      @defaults_store.save(
        source_kind: source_file ? "file" : "folder",
        source_folder: source_folder,
        source_file: source_file,
        destination_folder: destination_folder,
        title: title
      )
    end

    def present?(value)
      !value.to_s.empty?
    end

    def import_spotify_playlist(playlist_file)
      return nil unless playlist_file

      progress "Creating Spotify playlist from: #{File.expand_path(playlist_file)}"
      result = @spotify_client.import_playlist(file_path: playlist_file)
      progress "Spotify playlist created: #{result.fetch(:name)}; added #{result.fetch(:added)}/#{result.fetch(:total)} tracks."
      result
    end

    def select_store_and_approve_image(source_folder, destination_folder, source_file = nil, database = nil, smoke: false)
      loop do
        selected_file, database_image_name = select_image_candidate(source_folder, source_file, database)
        progress "Selected image file: #{File.expand_path(selected_file)}"
        @stdout.puts "Source image ready for approval: #{File.expand_path(selected_file)}"
        open_image(selected_file, label: "source")
        @stdout.print "Approve this source image? [y/N/q/d]: "

        answer = @stdin.gets
        if answer.nil?
          raise ImageApprovalRequiredError, "Image approval is required."
        end

        raise QuitRequested if quit_requested?(answer)

        if delete_requested?(answer)
          delete_source_image(selected_file)
          delete_database_image_record(database, database_image_name) if database_image_name
          raise SourceFileDeleted if source_file

          next
        end

        if approved?(answer)
          progress "Source image approved."
          stored_file = store_approved_image(selected_file, destination_folder, smoke:)
          delete_database_image_record(database, database_image_name) if database_image_name
          return stored_file
        end

        progress "Source image rejected; choosing another."
        raise ImageApprovalRequiredError, "Provided source file was rejected." if source_file
      end
    end

    def select_image_candidate(source_folder, source_file, database)
      return [source_file, nil] if source_file
      return select_database_image_candidate(source_folder, database) if database

      [select_random_image_file(source_folder), nil]
    end

    def select_image_file(source_folder, database)
      return select_random_image_file(source_folder) unless database

      select_database_image_candidate(source_folder, database).first
    end

    def select_database_image_candidate(source_folder, database)
      progress "Selecting random image from database: #{File.expand_path(database)}"
      found_record = false

      @image_url_database_factory.call(database).each_random_image_name do |image_name|
        found_record = true
        image_file = database_image_file_path(source_folder, image_name)
        progress "Random database image selected: #{image_name}"
        progress "Built source path from database image name: #{File.expand_path(image_file)}"
        return [image_file, image_name] if image_file?(image_file)

        progress "Database image file was not found or is not supported; selecting another record."
      end

      unless found_record
        raise EmptySourceFolderError, "No image names found in database table image_urls: #{database}"
      end

      raise EmptySourceFolderError, "No database image records resolved to an existing supported image file: #{database}"
    end

    def database_image_file_path(source_folder, image_name)
      normalized_image_name = normalize_database_image_name(image_name)
      normalized_path_name = normalize_database_path_name(normalized_image_name)
      File.expand_path(
        File.join(
          source_folder,
          normalized_path_name[0, 2].to_s,
          normalized_path_name[2, 2].to_s,
          normalized_image_name
        )
      )
    end

    def normalize_database_image_name(image_name)
      normalized = File.basename(image_name.to_s.strip.delete("\0").tr("\\", "/"))
      normalized = normalized.unicode_normalize(:nfc) if normalized.respond_to?(:unicode_normalize)
      normalized
    end

    def normalize_database_path_name(image_name)
      image_name.gsub(/\s+/, "_")
    end

    def select_random_image_file(folder)
      progress "Scanning folder: #{File.expand_path(folder)}"
      entries = selectable_entries(folder)

      if entries.empty?
        raise EmptySourceFolderError, "No image files found in source folder: #{folder}"
      end

      selected = entries.sample
      progress "Random item selected: #{File.expand_path(selected)}"
      return selected if File.file?(selected)

      progress "Selected item is a folder; descending."
      select_random_image_file(selected)
    end

    def selectable_entries(folder)
      Dir.children(folder)
         .map { |entry| File.join(folder, entry) }
         .select { |path| File.directory?(path) || image_file?(path) }
    end

    def image_file?(path)
      File.file?(path) && IMAGE_EXTENSIONS.include?(File.extname(path).downcase)
    end

    def ensure_destination_folder(destination_folder)
      if File.directory?(destination_folder)
        return true
      end

      if File.exist?(destination_folder)
        @stderr.puts "Destination path exists but is not a directory: #{destination_folder}"
        return false
      end

      progress "Destination folder does not exist; creating: #{File.expand_path(destination_folder)}"
      FileUtils.mkdir_p(destination_folder)
      true
    end

    def prepare_work_destination_folder(destination_folder, title)
      work_folder = File.join(destination_folder, filename_slug(title))

      if File.exist?(work_folder) && !File.directory?(work_folder)
        raise "Title destination path exists but is not a directory: #{work_folder}"
      end

      progress "Using title destination folder: #{File.expand_path(work_folder)}"
      FileUtils.mkdir_p(work_folder)
      File.expand_path(work_folder)
    end

    def move_to_destination(source_file, destination_folder)
      destination_file = unique_destination_file(destination_folder, File.basename(source_file))
      progress "Moving image to: #{File.expand_path(destination_file)}"
      FileUtils.mv(source_file, destination_file)
      File.expand_path(destination_file)
    end

    def copy_to_destination(source_file, destination_folder)
      destination_file = unique_destination_file(destination_folder, File.basename(source_file))
      progress "Copying image to: #{File.expand_path(destination_file)}"
      FileUtils.cp(source_file, destination_file)
      File.expand_path(destination_file)
    end

    def store_approved_image(source_file, destination_folder, smoke:)
      if smoke
        progress "Smoke mode enabled; copying approved image instead of moving it."
        copy_to_destination(source_file, destination_folder)
      else
        move_to_destination(source_file, destination_folder)
      end
    end

    def create_landscape_version_if_needed(base_image_file, destination_folder, memory_context)
      width, height = @image_inspector.dimensions(base_image_file)
      progress "Base image dimensions: #{width}x#{height}"

      if width > height
        progress "Base image is landscape; no 16:9 version needed."
        return nil
      end

      progress "Base image is not landscape; generating 16:9 version with GPT."
      landscape_file = unique_destination_file(
        destination_folder,
        "#{File.basename(base_image_file, ".*")}-16x9.png"
      )
      @image_enhancer.enhance(
        image_file: base_image_file,
        output_file: landscape_file,
        prompt: prompt_with_memories(LANDSCAPE_PROMPT, memory_context),
        size: :auto
      )
      landscape_file = File.expand_path(landscape_file)
      open_landscape_image(landscape_file)
      landscape_file
    end

    def create_album_cover(base_image_file, destination_folder, title, memory_context)
      progress "Generating 1:1 album cover with GPT."
      album_cover_file = unique_destination_file(
        destination_folder,
        "#{filename_slug(title)}.png"
      )
      @image_enhancer.enhance(
        image_file: base_image_file,
        output_file: album_cover_file,
        prompt: prompt_with_memories(album_cover_prompt(title), memory_context),
        size: "1024x1024"
      )
      album_cover_file = File.expand_path(album_cover_file)
      open_album_cover(album_cover_file)
      album_cover_file
    end

    def unique_destination_file(destination_folder, filename)
      extension = File.extname(filename).downcase
      base_name = File.basename(filename, ".*")
      destination_file = File.join(destination_folder, "#{base_name}#{extension}")
      counter = 2

      while File.exist?(destination_file)
        destination_file = File.join(destination_folder, "#{base_name}-#{counter}#{extension}")
        counter += 1
      end

      destination_file
    end

    def filename_slug(title)
      slug = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
      slug.empty? ? "enhanced-image" : slug
    end

    def approved?(answer)
      %w[y yes].include?(answer.strip.downcase)
    end

    def quit_requested?(answer)
      answer.strip.downcase == "q"
    end

    def delete_requested?(answer)
      answer.strip.downcase == "d"
    end

    def delete_source_image(source_file)
      progress "Deleting source image: #{File.expand_path(source_file)}"
      FileUtils.rm_f(source_file)
    end

    def delete_database_image_record(database, image_name)
      progress "Deleting database image record: #{image_name}"
      @image_url_database_factory.call(database).delete_image_name(image_name)
    end

    def open_landscape_image(landscape_file)
      open_image(landscape_file, label: "16:9")
    end

    def open_album_cover(album_cover_file)
      open_image(album_cover_file, label: "album cover")
    end

    def open_image(image_file, label:)
      progress "Opening #{label} image with the default application."
      return if @image_opener.open(image_file)

      @stderr.puts "Could not open #{label} image automatically: #{image_file}"
    end

    def album_cover_prompt(title)
      ALBUM_COVER_PROMPT_TEMPLATE.gsub("[TITLE]", title)
    end

    def notify_finished(title, album_cover_file)
      progress "Sending completion notification."
      @notifier.notify(
        title: "Daily Playlist Cover Creator",
        message: "Finished #{title}: #{File.basename(album_cover_file)}"
      )
    end

    def prompt_with_memories(prompt, memory_context)
      return prompt if memory_context.empty?

      "#{prompt}\n\nMemory context from previous successful runs:\n#{memory_context}"
    end

    def progress(message)
      @stdout.puts "[#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}] [progress] #{message}"
      @stdout.flush
    end

    class SystemImageOpener
      def open(path)
        system("open", path)
      end
    end

    class SystemNotifier
      def notify(title:, message:)
        script = <<~APPLESCRIPT
          display notification #{message.dump} with title #{title.dump}
        APPLESCRIPT

        system("osascript", "-e", script)
      end
    end

    class ImageInspector
      def dimensions(path)
        File.open(path, "rb") do |file|
          header = file.read(32)
          if header&.start_with?("\x89PNG\r\n\x1A\n".b)
            return header.byteslice(16, 8).unpack("N2")
          end
        end

        sips_dimensions(path)
      end

      private

      def sips_dimensions(path)
        output = IO.popen(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], err: File::NULL, &:read)
        width = output[/pixelWidth:\s*(\d+)/, 1]
        height = output[/pixelHeight:\s*(\d+)/, 1]
        return [width.to_i, height.to_i] if width && height

        raise "Unsupported image format for dimension check: #{path}"
      end
    end

    class MemoryStore
      MAX_RUNS = 5
      FILE_NAME = ".daily_playlist_cover_creator_memories.json"

      attr_reader :path

      def initialize(path = File.join(Dir.home, FILE_NAME))
        @path = path
      end

      def context
        runs = data.fetch("runs", []).last(MAX_RUNS)
        return "" if runs.empty?

        runs.map do |run|
          "- Playlist: #{run["playlist_title"]}; enhanced title: #{run["enhanced_title"]}; album cover: #{File.basename(run["album_cover_file"].to_s)}"
        end.join("\n")
      end

      def remember(playlist_title:, enhanced_title:, copied_file:, enhanced_file:, landscape_file:, album_cover_file:)
        current = data
        current["runs"] ||= []
        current["runs"] << {
          "created_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
          "playlist_title" => playlist_title,
          "enhanced_title" => enhanced_title,
          "copied_file" => copied_file,
          "enhanced_file" => enhanced_file,
          "landscape_file" => landscape_file,
          "album_cover_file" => album_cover_file
        }
        current["runs"] = current["runs"].last(MAX_RUNS)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(current))
      end

      private

      def data
        return { "runs" => [] } unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        { "runs" => [] }
      end
    end

    class DefaultsStore
      FILE_NAME = ".daily_playlist_cover_creator_defaults.json"

      attr_reader :path

      def initialize(path: File.join(Dir.home, FILE_NAME))
        @path = path
      end

      def load
        return {} unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        {}
      end

      def save(source_kind:, source_folder:, source_file:, destination_folder:, title:)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(
          path,
          JSON.pretty_generate(
            {
              "updated_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
              "source_kind" => source_kind,
              "source_folder" => source_folder,
              "source_file" => source_file,
              "destination_folder" => destination_folder,
              "title" => title
            }
          )
        )
      end
    end

    def parser(options = {})
      OptionParser.new do |opts|
        opts.banner = "Usage: daily-playlist-cover-creator --source-folder PATH --destination-folder PATH --title TITLE"
        opts.separator ""
        opts.separator "Missing values prompt with the last successful run's value as the default when available."
        opts.separator ""

        opts.on("-s", "--source-folder PATH", "Folder containing source files") do |path|
          options[:source_folder] = path
        end

        opts.on("-d", "--destination-folder PATH", "Folder for generated output files") do |path|
          options[:destination_folder] = path
        end

        opts.on("-t", "--title TITLE", "Title for the generated playlist cover") do |title|
          options[:title] = title
        end

        opts.on("-p", "--playlist FILE", "Playlist text file to import into Spotify") do |playlist|
          options[:playlist] = playlist
        end

        opts.on("--database PATH", "SQLite database with image_urls.image_name records") do |path|
          options[:database] = path
        end

        opts.on("--spotify-login", "Authorize Spotify and save a refresh token") do
          options[:spotify_login] = true
        end

        opts.on("--smoke", "Copy the approved source image instead of moving it") do
          options[:smoke] = true
        end

        opts.on("-f", "--file FILE", "Use this image file instead of selecting randomly") do |file|
          options[:file] = file
        end

        opts.on("-h", "--help", "Show this help") do
          @stdout.puts opts
          exit 0
        end
      end
    end
  end
end
