# frozen_string_literal: true

require "base64"
require "pathname"

module DailyPlaylistCoverCreator
  class GptImageEnhancer
    DEFAULT_MODEL = "gpt-image-1.5"
    DEFAULT_OUTPUT_FORMAT = :png
    SUPPORTED_CONTENT_TYPES = {
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".png" => "image/png",
      ".webp" => "image/webp"
    }.freeze

    def initialize(api_key: ENV["OPENAI_API_KEY"], model: ENV.fetch("OPENAI_IMAGE_MODEL", DEFAULT_MODEL), client_factory: nil)
      @api_key = api_key
      @model = model.to_s.empty? ? DEFAULT_MODEL : model
      @client_factory = client_factory
    end

    def enhance(image_file:, output_file:, prompt:, size: :auto)
      raise "OPENAI_API_KEY is required to enhance images with GPT." if @api_key.to_s.empty?

      require "openai"

      client = build_client
      response = client.images.edit(
        image: image_file_part(image_file),
        prompt: prompt,
        model: @model,
        output_format: DEFAULT_OUTPUT_FORMAT,
        size: size
      )

      encoded_image = response.data&.first&.b64_json
      raise "GPT image enhancement did not return image data." if encoded_image.to_s.empty?

      File.binwrite(output_file, Base64.decode64(encoded_image))
      File.expand_path(output_file)
    end

    private

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
end
