# frozen_string_literal: true

module DailyPlaylistCoverCreator
  class GptTitleSuggester
    DEFAULT_MODEL = "gpt-5.2"

    def initialize(api_key: ENV["OPENAI_API_KEY"], model: ENV.fetch("OPENAI_TEXT_MODEL", DEFAULT_MODEL))
      @api_key = api_key
      @model = model
    end

    def suggest(original_file:, playlist_title:, memory_context: "")
      raise "OPENAI_API_KEY is required to suggest an image title with GPT." if @api_key.to_s.empty?

      require "openai"

      client = OpenAI::Client.new(api_key: @api_key)
      response = client.responses.create(
        model: @model,
        input: prompt(original_file:, playlist_title:, memory_context:)
      )

      response.output_text.to_s.strip
    end

    private

    def prompt(original_file:, playlist_title:, memory_context:)
      <<~PROMPT
      Suggest a concise title for an enhanced daily playlist cover image.

      Playlist title: #{playlist_title}
      Enhanced image filename: #{File.basename(original_file)}
      #{memory_section(memory_context)}

        Requirements:
        - Return only the suggested title.
        - Use 2 to 6 words.
        - Do not include a file extension.
        - Do not include quotes.
        - Do not include punctuation unless it is essential.
      PROMPT
    end

    def memory_section(memory_context)
      return "" if memory_context.to_s.empty?

      "\nMemory context from previous successful runs:\n#{memory_context}"
    end
  end
end
