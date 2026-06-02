# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"

require_relative "../lib/daily_playlist_cover_creator/spotify_client"

class SpotifyClientTest < Minitest::Test
  def test_creates_public_playlist_from_playlist_file
    Dir.mktmpdir do |folder|
      playlist_file = File.join(folder, "Daily Mix.txt")
      File.write(playlist_file, "First Song\n")
      http = FakeHttp.new
      client = DailyPlaylistCoverCreator::SpotifyClient.new(access_token: "token", http:)

      result = client.import_playlist(file_path: playlist_file)

      create_playlist_request = http.requests.find { |request| request.path == "/v1/users/user-123/playlists" }
      create_playlist_body = JSON.parse(create_playlist_request.body)
      assert_equal "Daily Mix", create_playlist_body.fetch("name")
      assert_equal true, create_playlist_body.fetch("public")
      assert_equal "Daily Mix", result.fetch(:name)
      assert_equal 1, result.fetch(:added)
    end
  end

  class FakeHttp
    attr_reader :requests

    def initialize
      @requests = []
    end

    def call(request, _uri)
      @requests << request

      case request
      when Net::HTTP::Get
        get_response(request)
      when Net::HTTP::Post
        post_response(request)
      else
        FakeResponse.new(405, "{}")
      end
    end

    private

    def get_response(request)
      return FakeResponse.new(200, { id: "user-123" }.to_json) if request.path == "/v1/me"

      if request.path.start_with?("/v1/search")
        return FakeResponse.new(
          200,
          {
            tracks: {
              items: [
                {
                  uri: "spotify:track:first-song"
                }
              ]
            }
          }.to_json
        )
      end

      FakeResponse.new(404, "{}")
    end

    def post_response(request)
      return FakeResponse.new(201, playlist_response.to_json) if request.path == "/v1/users/user-123/playlists"
      return FakeResponse.new(201, { snapshot_id: "snapshot" }.to_json) if request.path == "/v1/playlists/playlist-123/items"

      FakeResponse.new(404, "{}")
    end

    def playlist_response
      {
        id: "playlist-123",
        external_urls: {
          spotify: "https://open.spotify.com/playlist/playlist-123"
        }
      }
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
