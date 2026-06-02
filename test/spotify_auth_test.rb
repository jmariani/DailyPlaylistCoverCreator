# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "stringio"

require_relative "../lib/daily_playlist_cover_creator/spotify_auth"

class SpotifyAuthTest < Minitest::Test
  def test_refreshes_access_token_from_saved_refresh_token
    without_spotify_access_token do
      token_store = FakeTokenStore.new("refresh_token" => "saved-refresh")
      http = FakeHttp.new(
        "access_token" => "fresh-access",
        "expires_in" => 3600
      )
      auth = DailyPlaylistCoverCreator::SpotifyAuth.new(
        client_id: "client-id",
        token_store:,
        http:,
        stdout: StringIO.new
      )

      assert_equal "fresh-access", auth.access_token
      assert_equal "grant_type=refresh_token&refresh_token=saved-refresh&client_id=client-id", http.requests.first.body
      assert_equal "fresh-access", token_store.saved.fetch(:access_token)
      assert_equal "saved-refresh", token_store.saved.fetch(:refresh_token)
    end
  end

  def test_requires_client_id_when_no_manual_token_or_saved_refresh_token_exists
    without_spotify_access_token do
      auth = DailyPlaylistCoverCreator::SpotifyAuth.new(
        client_id: nil,
        token_store: FakeTokenStore.new,
        stdout: StringIO.new
      )

      error = assert_raises(RuntimeError) { auth.access_token }

      assert_includes error.message, "SPOTIFY_CLIENT_ID is required"
    end
  end

  private

  def without_spotify_access_token
    previous = ENV.delete("SPOTIFY_ACCESS_TOKEN")
    yield
  ensure
    ENV["SPOTIFY_ACCESS_TOKEN"] = previous if previous
  end

  class FakeTokenStore
    attr_reader :saved

    def initialize(data = {})
      @data = data
      @saved = nil
    end

    def load
      @data
    end

    def save(access_token:, refresh_token:, expires_at:)
      @saved = { access_token:, refresh_token:, expires_at: }
    end
  end

  class FakeHttp
    attr_reader :requests

    def initialize(response)
      @response = response
      @requests = []
    end

    def call(request, _uri)
      @requests << request
      FakeResponse.new(200, @response.to_json)
    end
  end

  class FakeResponse
    attr_reader :code, :body

    def initialize(code, body)
      @code = code.to_s
      @body = body
    end

    def is_a?(klass)
      klass == Net::HTTPSuccess || super
    end
  end
end
