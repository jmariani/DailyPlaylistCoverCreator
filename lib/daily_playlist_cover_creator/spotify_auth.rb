# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "securerandom"
require "timeout"
require "uri"
require "webrick"

module DailyPlaylistCoverCreator
  class SpotifyAuth
    AUTHORIZE_URL = "https://accounts.spotify.com/authorize"
    TOKEN_URL = "https://accounts.spotify.com/api/token"
    DEFAULT_REDIRECT_URI = "http://127.0.0.1:4567/callback"
    DEFAULT_SCOPE = "playlist-modify-public"

    def initialize(
      client_id: ENV["SPOTIFY_CLIENT_ID"],
      redirect_uri: ENV.fetch("SPOTIFY_REDIRECT_URI", DEFAULT_REDIRECT_URI),
      token_store: SpotifyTokenStore.new,
      opener: ->(url) { system("open", url) },
      http: nil,
      stdout: $stdout
    )
      @client_id = client_id
      @redirect_uri = redirect_uri
      @token_store = token_store
      @opener = opener
      @http = http
      @stdout = stdout
    end

    def access_token
      return ENV["SPOTIFY_ACCESS_TOKEN"] unless ENV["SPOTIFY_ACCESS_TOKEN"].to_s.empty?

      saved = @token_store.load
      return refresh_access_token(saved.fetch("refresh_token")) if saved["refresh_token"]

      login
    end

    def login
      require_client_id!
      verifier = code_verifier
      state = SecureRandom.hex(16)
      callback = wait_for_callback do
        @stdout.puts "Opening Spotify login in your browser."
        @opener.call(authorization_url(verifier:, state:))
      end

      if callback.fetch(:state) != state
        raise "Spotify OAuth state did not match. Please try logging in again."
      end

      exchange_authorization_code(callback.fetch(:code), verifier)
    end

    private

    def authorization_url(verifier:, state:)
      uri = URI(AUTHORIZE_URL)
      uri.query = URI.encode_www_form(
        response_type: "code",
        client_id: @client_id,
        scope: DEFAULT_SCOPE,
        redirect_uri: @redirect_uri,
        state: state,
        code_challenge_method: "S256",
        code_challenge: code_challenge(verifier)
      )
      uri.to_s
    end

    def wait_for_callback
      uri = URI(@redirect_uri)
      queue = Queue.new
      server = WEBrick::HTTPServer.new(
        BindAddress: uri.host,
        Port: uri.port,
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )
      server.mount_proc(uri.path) do |request, response|
        if request.query["error"]
          response.status = 400
          response.body = "Spotify authorization failed. You can close this window."
          queue << { error: request.query["error"] }
        else
          response.status = 200
          response.body = "Spotify login complete. You can close this window."
          queue << { code: request.query.fetch("code"), state: request.query.fetch("state") }
        end
      end

      thread = Thread.new { server.start }
      yield
      result = Timeout.timeout(300) { queue.pop }
      raise "Spotify authorization failed: #{result.fetch(:error)}" if result[:error]

      result
    ensure
      server&.shutdown
      thread&.join
    end

    def exchange_authorization_code(code, verifier)
      response = token_request(
        grant_type: "authorization_code",
        code: code,
        redirect_uri: @redirect_uri,
        client_id: @client_id,
        code_verifier: verifier
      )
      save_tokens(response)
      response.fetch("access_token")
    end

    def refresh_access_token(refresh_token)
      require_client_id!
      response = token_request(
        grant_type: "refresh_token",
        refresh_token: refresh_token,
        client_id: @client_id
      )
      response["refresh_token"] ||= refresh_token
      save_tokens(response)
      response.fetch("access_token")
    end

    def token_request(params)
      uri = URI(TOKEN_URL)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(params)
      response = @http ? @http.call(request, uri) : perform_request(request, uri)

      unless response.is_a?(Net::HTTPSuccess)
        raise "Spotify OAuth token request failed: #{response.code} #{response.body}"
      end

      JSON.parse(response.body)
    end

    def perform_request(request, uri)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
    end

    def save_tokens(response)
      @token_store.save(
        access_token: response.fetch("access_token"),
        refresh_token: response.fetch("refresh_token"),
        expires_at: Time.now.to_i + response.fetch("expires_in", 3600).to_i
      )
    end

    def code_verifier
      Base64.urlsafe_encode64(SecureRandom.random_bytes(64)).delete("=")
    end

    def code_challenge(verifier)
      Base64.urlsafe_encode64(Digest::SHA256.digest(verifier)).delete("=")
    end

    def require_client_id!
      return unless @client_id.to_s.empty?

      raise "SPOTIFY_CLIENT_ID is required for Spotify OAuth login."
    end
  end

  class SpotifyTokenStore
    FILE_NAME = ".daily_playlist_cover_creator_spotify.json"

    attr_reader :path

    def initialize(path: File.join(Dir.home, FILE_NAME))
      @path = path
    end

    def load
      return {} unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    def save(access_token:, refresh_token:, expires_at:)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(
        path,
        JSON.pretty_generate(
          {
            "access_token" => access_token,
            "refresh_token" => refresh_token,
            "expires_at" => expires_at
          }
        )
      )
    end
  end
end
