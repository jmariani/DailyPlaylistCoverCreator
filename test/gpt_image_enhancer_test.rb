# frozen_string_literal: true

require "base64"
require "tmpdir"
require "minitest/autorun"

require_relative "../lib/daily_playlist_cover_creator/gpt_image_enhancer"

class GptImageEnhancerTest < Minitest::Test
  def test_uploads_image_with_explicit_content_type
    Dir.mktmpdir do |folder|
      image_file = File.join(folder, "cover.jpg")
      output_file = File.join(folder, "enhanced.png")
      File.write(image_file, "image data")
      client = FakeClient.new
      enhancer = DailyPlaylistCoverCreator::GptImageEnhancer.new(api_key: "key", client_factory: ->(_api_key) { client })

      enhancer.enhance(image_file:, output_file:, prompt: "enhance")

      uploaded_image = client.images.edits.first.fetch(:image)
      assert_equal "cover.jpg", uploaded_image.filename
      assert_equal "image/jpeg", uploaded_image.content_type
      assert_equal DailyPlaylistCoverCreator::GptImageEnhancer::DEFAULT_MODEL, client.images.edits.first.fetch(:model)
      assert_equal "enhanced image", File.read(output_file)
    end
  end

  def test_blank_model_uses_default_model
    Dir.mktmpdir do |folder|
      image_file = File.join(folder, "cover.jpg")
      output_file = File.join(folder, "enhanced.png")
      File.write(image_file, "image data")
      client = FakeClient.new
      enhancer = DailyPlaylistCoverCreator::GptImageEnhancer.new(api_key: "key", model: "", client_factory: ->(_api_key) { client })

      enhancer.enhance(image_file:, output_file:, prompt: "enhance")

      assert_equal DailyPlaylistCoverCreator::GptImageEnhancer::DEFAULT_MODEL, client.images.edits.first.fetch(:model)
    end
  end

  def test_rejects_unsupported_upload_content_type
    Dir.mktmpdir do |folder|
      image_file = File.join(folder, "cover.gif")
      output_file = File.join(folder, "enhanced.png")
      File.write(image_file, "image data")
      enhancer = DailyPlaylistCoverCreator::GptImageEnhancer.new(api_key: "key", client_factory: ->(_api_key) { FakeClient.new })

      error = assert_raises(RuntimeError) do
        enhancer.enhance(image_file:, output_file:, prompt: "enhance")
      end

      assert_includes error.message, "only supports JPEG, PNG, and WEBP"
    end
  end

  class FakeClient
    attr_reader :images

    def initialize
      @images = FakeImages.new
    end
  end

  class FakeImages
    attr_reader :edits

    def initialize
      @edits = []
    end

    def edit(params)
      @edits << params
      FakeResponse.new
    end
  end

  class FakeResponse
    def data
      [FakeImage.new]
    end
  end

  class FakeImage
    def b64_json
      Base64.strict_encode64("enhanced image")
    end
  end
end
