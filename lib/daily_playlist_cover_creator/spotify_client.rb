# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require_relative "spotify_auth"

module DailyPlaylistCoverCreator
  class SpotifyClient
    API_BASE = "https://api.spotify.com/v1"

    def initialize(access_token: ENV["SPOTIFY_ACCESS_TOKEN"], token_provider: SpotifyAuth.new, api_base: API_BASE, http: nil)
      @access_token = access_token
      @token_provider = token_provider
      @api_base = api_base.to_s.sub(%r{/+\z}, "")
      @http = http
    end

    def import_playlist(file_path:)
      @access_token = spotify_access_token

      playlist_name = File.basename(file_path, ".*")
      songs = File.readlines(file_path, chomp: true).map(&:strip).reject(&:empty?)
      user = get_json("/me")
      playlist = post_json(
        "/users/#{path_escape(user.fetch("id"))}/playlists",
        {
          name: playlist_name,
          public: true,
          description: "Created by Daily Playlist Cover Creator"
        }
      )

      found_tracks = []
      missing_songs = []
      songs.each do |song|
        track = search_track(song)
        if track
          found_tracks << track
        else
          missing_songs << song
        end
      end

      found_tracks.map { |track| track.fetch("uri") }.each_slice(100) do |uris|
        post_json("/playlists/#{path_escape(playlist.fetch("id"))}/items", { uris: uris })
      end

      {
        name: playlist_name,
        url: playlist.dig("external_urls", "spotify"),
        total: songs.length,
        added: found_tracks.length,
        missing: missing_songs
      }
    end

    private

    def spotify_access_token
      return @access_token unless @access_token.to_s.empty?

      @token_provider.access_token
    end

    def search_track(query)
      response = get_json("/search", q: query, type: "track", limit: 1)
      response.dig("tracks", "items")&.first
    end

    def get_json(path, params = {})
      uri = uri_for(path, params)
      request = Net::HTTP::Get.new(uri)
      request_json(request, uri)
    end

    def post_json(path, body)
      uri = uri_for(path)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)
      request_json(request, uri)
    end

    def request_json(request, uri)
      request["Authorization"] = "Bearer #{@access_token}"
      response = @http ? @http.call(request, uri) : perform_request(request, uri)

      unless response.is_a?(Net::HTTPSuccess)
        raise "Spotify API request failed: #{response.code} #{response.body}"
      end

      return {} if response.body.to_s.empty?

      JSON.parse(response.body)
    end

    def perform_request(request, uri)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
    end

    def uri_for(path, params = {})
      uri = URI("#{@api_base}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?
      uri
    end

    def path_escape(value)
      URI.encode_www_form_component(value)
    end
  end
end
