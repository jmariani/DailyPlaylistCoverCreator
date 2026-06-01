# frozen_string_literal: true

require "optparse"
require "fileutils"

module DailyPlaylistCoverCreator
  class CLI
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp .bmp .tif .tiff].freeze
    IMAGE_ENHANCEMENT_PROMPT = "enhance. cinematic. keep aspect ratio. do not add text."

    def self.run(
      argv,
      stdin: $stdin,
      stdout: $stdout,
      stderr: $stderr,
      image_opener: SystemImageOpener.new
    )
      new(stdin:, stdout:, stderr:, image_opener:).run(argv)
    end

    def initialize(stdin:, stdout:, stderr:, image_opener:)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @image_opener = image_opener
    end

    def run(argv)
      progress "Starting daily playlist cover creator."
      options = parse(argv)
      source_folder = options[:source_folder]
      destination_folder = options[:destination_folder]
      title = options[:title]

      unless source_folder
        source_folder = prompt_for_source_folder
      end

      unless destination_folder
        destination_folder = prompt_for_destination_folder
      end

      unless title
        title = prompt_for_title
      end

      if source_folder.empty?
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

      unless File.directory?(source_folder)
        @stderr.puts "Source folder does not exist or is not a directory: #{source_folder}"
        return 1
      end

      unless ensure_destination_folder(destination_folder)
        return 1
      end

      progress "Inputs validated."
      copied_file = select_copy_and_approve_image(source_folder, destination_folder)

      @stdout.puts "Source folder: #{File.expand_path(source_folder)}"
      @stdout.puts "Destination folder: #{File.expand_path(destination_folder)}"
      @stdout.puts "Title: #{title}"
      @stdout.puts "Image enhancement prompt: #{IMAGE_ENHANCEMENT_PROMPT}"
      @stdout.puts "Copied image: #{copied_file}"
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

    def select_copy_and_approve_image(source_folder, destination_folder)
      loop do
        selected_file = select_random_image_file(source_folder)
        progress "Selected image file: #{File.expand_path(selected_file)}"
        copied_file = copy_to_destination(selected_file, destination_folder)
        @stdout.puts "Copied image ready for approval: #{copied_file}"
        open_copied_image(copied_file)
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

    def copy_to_destination(source_file, destination_folder)
      destination_file = unique_destination_file(destination_folder, File.basename(source_file))
      progress "Copying image to: #{File.expand_path(destination_file)}"
      FileUtils.cp(source_file, destination_file)
      File.expand_path(destination_file)
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

    def approved?(answer)
      %w[y yes].include?(answer.strip.downcase)
    end

    def open_copied_image(copied_file)
      progress "Opening copied image with the default application."
      return if @image_opener.open(copied_file)

      @stderr.puts "Could not open copied image automatically: #{copied_file}"
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

        opts.on("-h", "--help", "Show this help") do
          @stdout.puts opts
          exit 0
        end
      end
    end
  end
end
