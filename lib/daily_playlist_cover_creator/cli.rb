# frozen_string_literal: true

require "optparse"
require "fileutils"
require "json"
require_relative "gpt_image_enhancer"
require_relative "gpt_title_suggester"

module DailyPlaylistCoverCreator
  class CLI
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze
    IMAGE_ENHANCEMENT_PROMPT = "Apply cinematic enhancements to this image while preserving the original aspect ratio. Improve lighting, contrast, color grading, depth, sharpness, and overall visual polish. Keep the image composition faithful to the original. Do not add any text, letters, captions, logos, watermarks, or typography."
    ALBUM_COVER_PROMPT_TEMPLATE = "Create a 1:1 album cover using this image as base. The title color is complementary to the background. Justify the title. The title is %title%"

    def self.run(
      argv,
      stdin: $stdin,
      stdout: $stdout,
      stderr: $stderr,
      image_opener: SystemImageOpener.new,
      image_enhancer: GptImageEnhancer.new,
      title_suggester: GptTitleSuggester.new,
      image_inspector: ImageInspector.new,
      image_normalizer: SipsImageNormalizer.new,
      notifier: SystemNotifier.new,
      memory_store_factory: ->(destination_folder) { MemoryStore.new(destination_folder) }
    )
      new(
        stdin:,
        stdout:,
        stderr:,
        image_opener:,
        image_enhancer:,
        title_suggester:,
        image_inspector:,
        image_normalizer:,
        notifier:,
        memory_store_factory:
      ).run(argv)
    end

    def initialize(stdin:, stdout:, stderr:, image_opener:, image_enhancer:, title_suggester:, image_inspector:, image_normalizer:, notifier:, memory_store_factory:)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @image_opener = image_opener
      @image_enhancer = image_enhancer
      @title_suggester = title_suggester
      @image_inspector = image_inspector
      @image_normalizer = image_normalizer
      @notifier = notifier
      @memory_store_factory = memory_store_factory
    end

    def run(argv)
      progress "Starting daily playlist cover creator."
      options = parse(argv)
      source_folder = options[:source_folder]
      destination_folder = options[:destination_folder]
      title = options[:title]
      source_file = options[:file]

      unless source_folder || source_file
        source_folder = prompt_for_source_folder
      end

      unless destination_folder
        destination_folder = prompt_for_destination_folder
      end

      unless title
        title = prompt_for_title
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

      unless ensure_destination_folder(destination_folder)
        return 1
      end

      progress "Inputs validated."
      destination_folder = prepare_work_destination_folder(destination_folder, title)
      memory_store = @memory_store_factory.call(destination_folder)
      memory_context = memory_store.context
      progress "Loaded GPT memories from: #{memory_store.path}"
      copied_file = select_copy_and_approve_image(source_folder, destination_folder, source_file)
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
      notify_finished(title, album_cover_file)

      @stdout.puts "Source folder: #{File.expand_path(source_folder)}" if source_folder
      @stdout.puts "Source file: #{File.expand_path(source_file)}" if source_file
      @stdout.puts "Destination folder: #{File.expand_path(destination_folder)}"
      @stdout.puts "Title: #{title}"
      @stdout.puts "Image enhancement prompt: #{IMAGE_ENHANCEMENT_PROMPT}"
      @stdout.puts "Copied image: #{copied_file}"
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

    def prompt_for_source_folder
      progress "Source folder was not provided."
      @stdout.print "Enter source folder: "
      @stdin.gets&.chomp.to_s
    end

    def prompt_for_destination_folder
      progress "Destination folder was not provided."
      @stdout.print "Enter destination folder: "
      @stdin.gets&.chomp.to_s
    end

    def prompt_for_title
      progress "Title was not provided."
      @stdout.print "Enter title: "
      @stdin.gets&.chomp.to_s
    end

    def select_copy_and_approve_image(source_folder, destination_folder, source_file = nil)
      loop do
        selected_file = source_file || select_random_image_file(source_folder)
        progress "Selected image file: #{File.expand_path(selected_file)}"
        copied_file = copy_to_destination(selected_file, destination_folder)
        @stdout.puts "Copied image ready for approval: #{copied_file}"
        open_image(copied_file, label: "copied")
        @stdout.print "Approve this copied image? [y/N]: "

        answer = @stdin.gets
        if answer.nil?
          raise ImageApprovalRequiredError, "Image approval is required."
        end

        if approved?(answer)
          progress "Copied image approved."
          return copied_file
        end

        progress "Copied image rejected; removing it and choosing another."
        FileUtils.rm_f(copied_file)
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

    def copy_to_destination(source_file, destination_folder)
      destination_file = unique_destination_file(destination_folder, File.basename(source_file))
      progress "Copying image to: #{File.expand_path(destination_file)}"
      FileUtils.cp(source_file, destination_file)
      File.expand_path(destination_file)
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

      progress "Requesting GPT title for enhanced image."
      suggested_title = @title_suggester.suggest(original_file: temporary_enhanced_file, playlist_title:, memory_context:)
      progress "GPT title received for enhanced image: #{suggested_title}"

      enhanced_file = unique_destination_file(destination_folder, "#{filename_slug(suggested_title)}.png")
      FileUtils.mv(temporary_enhanced_file, enhanced_file)
      [File.expand_path(enhanced_file), suggested_title]
    end

    def normalize_for_gpt(image_file, destination_folder)
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

      def initialize(destination_folder)
        @path = File.join(destination_folder, FILE_NAME)
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

    def parser(options = {})
      OptionParser.new do |opts|
        opts.banner = "Usage: daily-playlist-cover-creator --source-folder PATH --destination-folder PATH --title TITLE"

        opts.on("-s", "--source-folder PATH", "Folder containing source files") do |path|
          options[:source_folder] = path
        end

        opts.on("-d", "--destination-folder PATH", "Folder for generated output files") do |path|
          options[:destination_folder] = path
        end

        opts.on("-t", "--title TITLE", "Title for the generated playlist cover") do |title|
          options[:title] = title
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
