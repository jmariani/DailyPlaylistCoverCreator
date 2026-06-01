# frozen_string_literal: true

require "optparse"

module DailyPlaylistCoverCreator
  class CLI
    def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      new(stdin:, stdout:, stderr:).run(argv)
    end

    def initialize(stdin:, stdout:, stderr:)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
    end

    def run(argv)
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

      unless File.directory?(destination_folder)
        @stderr.puts "Destination folder does not exist or is not a directory: #{destination_folder}"
        return 1
      end

      @stdout.puts "Source folder: #{File.expand_path(source_folder)}"
      @stdout.puts "Destination folder: #{File.expand_path(destination_folder)}"
      @stdout.puts "Title: #{title}"
      0
    rescue OptionParser::ParseError => e
      @stderr.puts e.message
      @stderr.puts parser
      1
    end

    private

    def parse(argv)
      options = {}
      parser(options).parse!(argv)
      options
    end

    def prompt_for_source_folder
      @stdout.print "Enter source folder: "
      @stdin.gets&.chomp.to_s
    end

    def prompt_for_destination_folder
      @stdout.print "Enter destination folder: "
      @stdin.gets&.chomp.to_s
    end

    def prompt_for_title
      @stdout.print "Enter title: "
      @stdin.gets&.chomp.to_s
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
