# frozen_string_literal: true

require "base64"
require "tmpdir"
require "minitest/autorun"

require_relative "../lib/daily_playlist_cover_creator/gpt_image_enhancer"

class GptImageEnhancerTest < Minitest::Test
  def test_default_model_uses_latest_image_model
    assert_equal "gpt-image-1.5", DailyPlaylistCoverCreator::GptImageEnhancer::LATEST_IMAGE_MODEL
    assert_equal DailyPlaylistCoverCreator::GptImageEnhancer::LATEST_IMAGE_MODEL, DailyPlaylistCoverCreator::GptImageEnhancer::DEFAULT_MODEL
  end

  def test_uploads_image_with_explicit_content_type
    Dir.mktmpdir do |folder|
      image_file = File.join(folder, "cover.jpg")
      output_file = File.join(folder, "enhanced.png")
      File.write(image_file, "image data")
      client = FakeClient.new
      resolver = FakeResolver.new("gpt-image-2")
      enhancer = DailyPlaylistCoverCreator::GptImageEnhancer.new(api_key: "key", image_model_resolver: resolver, client_factory: ->(_api_key) { client })

      enhancer.enhance(image_file:, output_file:, prompt: "enhance")

      uploaded_image = client.images.edits.first.fetch(:image)
      assert_equal "cover.jpg", uploaded_image.filename
      assert_equal "image/jpeg", uploaded_image.content_type
      assert_equal "gpt-image-2", client.images.edits.first.fetch(:model)
      assert_equal 1, resolver.calls
      assert_equal "enhanced image", File.read(output_file)
    end
  end

  def test_blank_model_asks_resolver_for_latest_model
    Dir.mktmpdir do |folder|
      image_file = File.join(folder, "cover.jpg")
      output_file = File.join(folder, "enhanced.png")
      File.write(image_file, "image data")
      client = FakeClient.new
      resolver = FakeResolver.new("gpt-image-2")
      enhancer = DailyPlaylistCoverCreator::GptImageEnhancer.new(api_key: "key", model: "", image_model_resolver: resolver, client_factory: ->(_api_key) { client })

      enhancer.enhance(image_file:, output_file:, prompt: "enhance")

      assert_equal "gpt-image-2", client.images.edits.first.fetch(:model)
      assert_equal 1, resolver.calls
    end
  end

  def test_explicit_model_override_skips_resolver
    Dir.mktmpdir do |folder|
      image_file = File.join(folder, "cover.jpg")
      output_file = File.join(folder, "enhanced.png")
      File.write(image_file, "image data")
      client = FakeClient.new
      resolver = FakeResolver.new("gpt-image-2")
      enhancer = DailyPlaylistCoverCreator::GptImageEnhancer.new(api_key: "key", model: "gpt-image-custom", image_model_resolver: resolver, client_factory: ->(_api_key) { client })

      enhancer.enhance(image_file:, output_file:, prompt: "enhance")

      assert_equal "gpt-image-custom", client.images.edits.first.fetch(:model)
      assert_equal 0, resolver.calls
    end
  end

  def test_model_resolver_asks_gpt_for_latest_image_model
    client = FakeModelClient.new("gpt-image-2")
    resolver = DailyPlaylistCoverCreator::GptImageModelResolver.new(api_key: "key", client_factory: ->(_api_key) { client })

    assert_equal "gpt-image-2", resolver.latest_model
    assert_equal "gpt-5.2", client.responses.creates.first.fetch(:model)
    assert_includes client.responses.creates.first.fetch(:input), "latest available GPT Image model"
  end

  def test_model_resolver_falls_back_when_gpt_answer_is_not_an_image_model
    client = FakeModelClient.new("use the best one")
    resolver = DailyPlaylistCoverCreator::GptImageModelResolver.new(api_key: "key", fallback_model: "gpt-image-1.5", client_factory: ->(_api_key) { client })

    assert_equal "gpt-image-1.5", resolver.latest_model
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

  class FakeResolver
    attr_reader :calls

    def initialize(model)
      @model = model
      @calls = 0
    end

    def latest_model
      @calls += 1
      @model
    end
  end

  class FakeModelClient
    attr_reader :responses

    def initialize(output_text)
      @responses = FakeResponses.new(output_text)
    end
  end

  class FakeResponses
    attr_reader :creates

    def initialize(output_text)
      @output_text = output_text
      @creates = []
    end

    def create(params)
      @creates << params
      FakeTextResponse.new(@output_text)
    end
  end

  class FakeTextResponse
    attr_reader :output_text

    def initialize(output_text)
      @output_text = output_text
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
