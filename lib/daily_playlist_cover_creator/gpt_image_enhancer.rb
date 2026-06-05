# frozen_string_literal: true

require "base64"
require "pathname"

module DailyPlaylistCoverCreator
  class GptImageEnhancer
    LATEST_IMAGE_MODEL = "gpt-image-1.5"
    DEFAULT_MODEL = LATEST_IMAGE_MODEL
    DEFAULT_OUTPUT_FORMAT = :png
    DEFAULT_QUALITY = :high
    SUPPORTED_CONTENT_TYPES = {
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".png" => "image/png",
      ".webp" => "image/webp"
    }.freeze

    def initialize(api_key: ENV["OPENAI_API_KEY"], model: ENV["OPENAI_IMAGE_MODEL"], image_model_resolver: nil, client_factory: nil)
      @api_key = api_key
      @model = model.to_s.empty? ? nil : model
      @image_model_resolver = image_model_resolver
      @client_factory = client_factory
    end

    def enhance(image_file:, output_file:, prompt:, size: :auto)
      raise "OPENAI_API_KEY is required to enhance images with GPT." if @api_key.to_s.empty?

      require "openai"

      client = build_client
      response = client.images.edit(
        image: image_file_part(image_file),
        prompt: prompt,
        model: image_model,
        output_format: DEFAULT_OUTPUT_FORMAT,
        quality: DEFAULT_QUALITY,
        size: size
      )

      encoded_image = response.data&.first&.b64_json
      raise "GPT image enhancement did not return image data." if encoded_image.to_s.empty?

      File.binwrite(output_file, Base64.decode64(encoded_image))
      File.expand_path(output_file)
    end

    private

    def image_model
      return @model if @model

      @resolved_model ||= image_model_resolver.latest_model
    end

    def image_model_resolver
      @image_model_resolver ||= GptImageModelResolver.new(api_key: @api_key, fallback_model: DEFAULT_MODEL)
    end

    def image_file_part(image_file)
      content_type = content_type_for(image_file)
      OpenAI::FilePart.new(
        Pathname.new(image_file),
        filename: File.basename(image_file),
        content_type: content_type
      )
    end

    def build_client
      return @client_factory.call(@api_key) if @client_factory

      OpenAI::Client.new(api_key: @api_key)
    end

    def content_type_for(image_file)
      extension = File.extname(image_file).downcase
      SUPPORTED_CONTENT_TYPES.fetch(extension) do
        raise "GPT image enhancement only supports JPEG, PNG, and WEBP files: #{image_file}"
      end
    end
  end

  class GptImageModelResolver
    DEFAULT_TEXT_MODEL = "gpt-5.2"
    IMAGE_MODEL_PATTERN = /\A(?:gpt-image-[a-z0-9.-]+|chatgpt-image-latest)\z/

    def initialize(api_key: ENV["OPENAI_API_KEY"], text_model: ENV.fetch("OPENAI_TEXT_MODEL", DEFAULT_TEXT_MODEL), fallback_model: GptImageEnhancer::LATEST_IMAGE_MODEL, client_factory: nil)
      @api_key = api_key
      @text_model = text_model.to_s.empty? ? DEFAULT_TEXT_MODEL : text_model
      @fallback_model = fallback_model
      @client_factory = client_factory
    end

    def latest_model
      require "openai"

      candidate = ask_gpt_for_latest_model
      return candidate if valid_image_model?(candidate)

      @fallback_model
    rescue StandardError
      @fallback_model
    end

    private

    def ask_gpt_for_latest_model
      response = build_client.responses.create(
        model: @text_model,
        input: latest_model_prompt
      )

      response.output_text.to_s.strip.gsub(/[`"']/, "").split(/\s+/).first.to_s
    end

    def latest_model_prompt
      <<~PROMPT
        Return only the OpenAI Images API model ID for the latest available GPT Image model that supports /v1/images/edits.

        Requirements:
        - Return only one model ID.
        - Do not include prose, markdown, quotes, or punctuation.
        - The answer must start with gpt-image- or be chatgpt-image-latest.
        - If uncertain, return #{GptImageEnhancer::LATEST_IMAGE_MODEL}.
      PROMPT
    end

    def build_client
      return @client_factory.call(@api_key) if @client_factory

      OpenAI::Client.new(api_key: @api_key)
    end

    def valid_image_model?(model)
      IMAGE_MODEL_PATTERN.match?(model)
    end
  end
end
