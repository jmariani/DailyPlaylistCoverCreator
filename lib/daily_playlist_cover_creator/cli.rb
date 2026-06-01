# frozen_string_literal: true

require "optparse"

module DailyPlaylistCoverCreator
  class CLI
    def self.run(argv, stdout: $stdout, stderr: $stderr)
      new(stdout:, stderr:).run(argv)
    end

    def initialize(stdout:, stderr:)
      @stdout = stdout
      @stderr = stderr
    end

    def run(argv)
      options = parse(argv)
      source_folder = options[:source_folder]

      unless source_folder
        @stderr.puts "Missing required option: --source-folder"
        @stderr.puts parser
        return 1
      end

      unless File.directory?(source_folder)
        @stderr.puts "Source folder does not exist or is not a directory: #{source_folder}"
        return 1
      end

      @stdout.puts "Source folder: #{File.expand_path(source_folder)}"
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

    def parser(options = {})
      OptionParser.new do |opts|
        opts.banner = "Usage: daily-playlist-cover-creator --source-folder PATH"

        opts.on("--source-folder PATH", "Folder containing source files") do |path|
          options[:source_folder] = path
        end

        opts.on("-h", "--help", "Show this help") do
          @stdout.puts opts
          exit 0
        end
      end
    end
  end
end
