# frozen_string_literal: true

require "optparse"
require "fileutils"
require "json"
require_relative "gpt_image_enhancer"
require_relative "spotify_client"

module DailyPlaylistCoverCreator
  class CLI
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze
    IMAGE_ENHANCEMENT_PROMPT = "Enhance this image with a bright, well-lit, high-end editorial look while preserving the original composition and aspect ratio. Use daylight-balanced exposure, lifted shadows, clear midtone detail, luminous color, natural contrast, vibrant highlights, refined color grading, sharpness, depth, dynamic range, and overall visual polish. Keep blacks detailed rather than crushed. The final image should feel fresh, vivid, and clearly illuminated. Do not make it dark, moody, noir, low-key, shadow-heavy, muddy, or underexposed. Keep the scene faithful to the source image. Do not add text, captions, logos, typography, watermarks, or new objects."
    ALBUM_COVER_PROMPT_TEMPLATE = "Create a finished 1:1 album cover using this image as the visual base. Make it feel like bright, polished, professional cover art, not a simple crop. Preserve the core subject and mood, but improve the square composition with daylight-balanced exposure, lifted shadows, clear midtone detail, luminous color, natural contrast, depth, crisp detail, vibrant highlights, and tasteful graphic design. Keep blacks detailed rather than crushed. The cover should feel fresh, vivid, readable, and clearly illuminated. Do not make it dark, moody, noir, low-key, shadow-heavy, muddy, or underexposed. Add the title as clean, legible, justified typography. Choose a typeface style that relates to the image subject, atmosphere, era, genre, and mood. Choose a title color that is complementary to the background and has strong readable contrast. Do not add any text other than the title. The title is %title%"

    def self.run(
      argv,
      stdin: $stdin,
      stdout: $stdout,
      stderr: $stderr,
      image_opener: SystemImageOpener.new,
      image_enhancer: GptImageEnhancer.new,
      image_inspector: ImageInspector.new,
      image_normalizer: SipsImageNormalizer.new,
      notifier: SystemNotifier.new,
      spotify_auth: nil,
      spotify_client: nil,
      defaults_store: DefaultsStore.new,
      memory_store_factory: ->(_destination_folder) { MemoryStore.new }
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
        image_normalizer:,
        notifier:,
        spotify_auth:,
        spotify_client:,
        defaults_store:,
        memory_store_factory:
      ).run(argv)
    end

    def initialize(stdin:, stdout:, stderr:, image_opener:, image_enhancer:, image_inspector:, image_normalizer:, notifier:, spotify_auth:, spotify_client:, defaults_store:, memory_store_factory:)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @image_opener = image_opener
      @image_enhancer = image_enhancer
      @image_inspector = image_inspector
      @image_normalizer = image_normalizer
      @notifier = notifier
      @spotify_auth = spotify_auth
      @spotify_client = spotify_client
      @defaults_store = defaults_store
      @memory_store_factory = memory_store_factory
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
      memory_store = @memory_store_factory.call(destination_folder)
      memory_context = memory_store.context
      progress "Loaded GPT memories from: #{memory_store.path}"
      copied_file = select_store_and_approve_image(source_folder, destination_folder, source_file, smoke:)
      enhanced_file, enhanced_title = enhance_and_name_image(copied_file, destination_folder, title, memory_context)
      open_enhanced_image(enhanced_file)
      landscape_file = create_landscape_version_if_needed(enhanced_file, destination_folder, memory_context)
      album_cover_file = create_album_cover(landscape_file || enhanced_file, destination_folder, title, memory_context)
      memory_store.remember(
        playlist_title: title,
        enhanced_title: enhanced_title,
        copied_file: copied_file,
        enhanced_file: enhanced_file,
        landscape_file: landscape_file,
        album_cover_file: album_cover_file
      )
      progress "Saved GPT memories to: #{memory_store.path}"
      remember_defaults(
        source_folder: source_folder,
        source_file: source_file,
        destination_folder: destination_root,
        title: title
      )
      notify_finished(title, album_cover_file)

      @stdout.puts "Source folder: #{File.expand_path(source_folder)}" if source_folder
      @stdout.puts "Source file: #{File.expand_path(source_file)}" if source_file
      @stdout.puts "Destination folder: #{File.expand_path(destination_folder)}"
      @stdout.puts "Title: #{title}"
      @stdout.puts "Playlist file: #{File.expand_path(playlist)}" if playlist
      if spotify_playlist
        @stdout.puts "Spotify playlist: #{spotify_playlist.fetch(:name)}"
        @stdout.puts "Spotify playlist URL: #{spotify_playlist.fetch(:url)}" if spotify_playlist.fetch(:url)
        @stdout.puts "Spotify tracks added: #{spotify_playlist.fetch(:added)}/#{spotify_playlist.fetch(:total)}"
        @stdout.puts "Spotify tracks not found: #{spotify_playlist.fetch(:missing).join(", ")}" unless spotify_playlist.fetch(:missing).empty?
      end
      @stdout.puts "Image enhancement prompt: #{IMAGE_ENHANCEMENT_PROMPT}"
      @stdout.puts "#{smoke ? "Copied" : "Moved"} image: #{copied_file}"
      @stdout.puts "Enhanced image: #{enhanced_file}"
      @stdout.puts "16:9 image: #{landscape_file}" if landscape_file
      @stdout.puts "Album cover: #{album_cover_file}"
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
    rescue StandardError => e
      @stderr.puts e.message
      1
    end

    private

    EmptySourceFolderError = Class.new(StandardError)
    ImageApprovalRequiredError = Class.new(StandardError)

    def parse(argv)
      options = {}
      parser(options).parse!(argv)
      options
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

    def select_store_and_approve_image(source_folder, destination_folder, source_file = nil, smoke: false)
      loop do
        selected_file = source_file || select_random_image_file(source_folder)
        progress "Selected image file: #{File.expand_path(selected_file)}"
        @stdout.puts "Source image ready for approval: #{File.expand_path(selected_file)}"
        open_image(selected_file, label: "source")
        @stdout.print "Approve this source image? [y/N]: "

        answer = @stdin.gets
        if answer.nil?
          raise ImageApprovalRequiredError, "Image approval is required."
        end

        if approved?(answer)
          progress "Source image approved."
          return store_approved_image(selected_file, destination_folder, smoke:)
        end

        progress "Source image rejected; choosing another."
        raise ImageApprovalRequiredError, "Provided source file was rejected." if source_file
      end
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

    def enhance_and_name_image(copied_file, destination_folder, playlist_title, memory_context)
      progress "Enhancing approved image with GPT."
      normalized_file = normalize_for_gpt(copied_file, destination_folder)
      temporary_enhanced_file = unique_destination_file(destination_folder, "enhanced.png")
      @image_enhancer.enhance(
        image_file: normalized_file,
        output_file: temporary_enhanced_file,
        prompt: prompt_with_memories(IMAGE_ENHANCEMENT_PROMPT, memory_context)
      )

      enhanced_file = unique_destination_file(destination_folder, "#{File.basename(copied_file, ".*")}-enh.png")
      FileUtils.mv(temporary_enhanced_file, enhanced_file)
      [File.expand_path(enhanced_file), playlist_title]
    end

    def normalize_for_gpt(image_file, destination_folder)
      if image_file?(image_file)
        progress "Using original image for GPT upload without JPEG normalization: #{File.expand_path(image_file)}"
        return File.expand_path(image_file)
      end

      normalized_file = unique_destination_file(
        destination_folder,
        "#{File.basename(image_file, ".*")}-normalized.jpg"
      )
      progress "Normalizing image for GPT upload: #{File.expand_path(normalized_file)}"
      @image_normalizer.normalize(image_file:, output_file: normalized_file)
      File.expand_path(normalized_file)
    end

    def create_landscape_version_if_needed(enhanced_file, destination_folder, memory_context)
      width, height = @image_inspector.dimensions(enhanced_file)
      progress "Enhanced image dimensions: #{width}x#{height}"

      if width > height
        progress "Enhanced image is landscape; no 16:9 version needed."
        return nil
      end

      progress "Enhanced image is not landscape; generating 16:9 version with GPT."
      landscape_file = unique_destination_file(
        destination_folder,
        "#{File.basename(enhanced_file, ".*")}-16x9.png"
      )
      @image_enhancer.enhance(
        image_file: enhanced_file,
        output_file: landscape_file,
        prompt: prompt_with_memories("#{IMAGE_ENHANCEMENT_PROMPT} Generate a 16:9 landscape version.", memory_context),
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

    def open_enhanced_image(enhanced_file)
      open_image(enhanced_file, label: "enhanced")
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
      ALBUM_COVER_PROMPT_TEMPLATE.gsub("%title%", title)
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

          raise "Unsupported enhanced image format for dimension check: #{path}"
        end
      end
    end

    class SipsImageNormalizer
      def normalize(image_file:, output_file:)
        unless system("sips", "-s", "format", "jpeg", image_file, "--out", output_file, out: File::NULL, err: File::NULL)
          raise "Could not normalize image for GPT upload: #{image_file}"
        end

        output_file
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
