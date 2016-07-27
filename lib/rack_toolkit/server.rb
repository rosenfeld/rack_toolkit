# frozen_string_literal: true

require 'puma'
require 'net/http'
require 'uri'
require 'socket'
require 'set'
require 'http-cookie'
require_relative 'response_enhancer'

module RackToolkit
  class Server
    attr_accessor :app, :default_env, :referer, :default_headers
    attr_reader :bind_host, :host, :server, :default_domain, :last_response, :http, :cookie_jar,
      :env, :env_from_server, :rack_env, :virtual_hosts

    def initialize(app: nil, port: nil, bind_host: '127.0.0.1', virtual_hosts: [], host: nil,
                   dynamic_app: nil, default_env: {}, default_domain: nil, default_headers: {},
                   start: false)
      @app, @port, @bind_host, @default_env, @default_domain, @default_headers =
        app, port, bind_host, default_env, default_domain, default_headers
      @host = host || bind_host
      @virtual_hosts = Set.new virtual_hosts
      @virtual_hosts << default_domain if default_domain
      @virtual_hosts << host
      @dynamic_app = dynamic_app || default_dynamic_app
      @request_env = {}
      @referer = nil
      @cookie_jar = HTTP::CookieJar.new
      self.start if start
    end

    def start
      @server = Puma::Server.new(@dynamic_app)
      @server.add_tcp_listener @host, port
      @server_thread = @server.run
      @http = Net::HTTP.start @host, port
    end
    
    def stop
      @http.finish rescue nil # ignore errors on finish
      @server.stop true
    end

    def default_domain=(default_domain)
      @default_domain = default_domain
      @virtual_hosts << default_domain if default_domain
    end

    def base_uri
      @base_uri ||= URI("http://#{host}:#{port}")
    end

    def reset_session!
      @cookie_jar.clear
      self.referer = nil
    end

    # response = get('/'); body = response.body; headers = response.to_hash
    # response['set-cookie'] # => string
    # response.get_fields('set-cookie') # => array # same as response.to_hash['set-cookie']
    def get(url_or_path, params: nil, headers: {}, env_override: {}, follow_redirect: true,
            redirect_limit: 5)
      wrap_response(url_or_path, headers, env_override, params, follow_redirect,
                    redirect_limit) do |uri, h, http|
        http.get(uri.path.empty? ? '/' : uri.path, h)
      end
    end

    def post(url_or_path, params: nil, query_params: nil, headers: {}, env_override: {},
             follow_redirect: true, redirect_limit: 5)
      wrap_response(url_or_path, headers, env_override, params, follow_redirect,
                    redirect_limit) do |uri, h, http|
        req = Net::HTTP::Post.new uri, h
        req.form_data = params if params
        http.request req
      end
    end

    def post_data(url_or_path, data, query_params: nil, headers: {},
                  env_override: {}, follow_redirect: true, redirect_limit: 5)
      wrap_response(url_or_path, headers, env_override, query_params, follow_redirect,
                    redirect_limit) do |uri, h, http|
        http.post(uri, data, h)
      end
    end

    def follow_redirect!(limit: 5, env_override: {})
      get @last_response['location'], redirect_limit: limit - 1, env_override: {}
    end

    def port
      @port ||= find_free_tcp_port
    end

    private

    def find_free_tcp_port
      server = TCPServer.new(bind_host, 0)
      server.addr[1]
    ensure
      server.close
    end

    NO_DEFINED_APP_RESPONSE =[ 500, {}, [ 'No app was defined for server' ] ].freeze
    def default_dynamic_app
      ->(env) do
        return NO_DEFINED_APP_RESPONSE unless app
        @env_from_server = env.clone
        @env = (@rack_env = env.merge(default_env).merge(@request_env)).clone
        app.call @rack_env
      end
    end

    def wrap_response(url_or_path, headers, env_override, params, follow_redirect, redirect_limit)
      uri = normalize_uri(url_or_path, params)
      h = prepare_headers headers, env_override, uri
      response = uri.host == host ? yield(uri, h, @http) :
          Net::HTTP.start(uri.host, uri.port){|http| yield uri, h, http }
      @last_response = response.extend ResponseEnhancer
      store_cookies uri
      self.referer = @original_uri.to_s
      @request_env = {}
      handle_redirect redirect_limit, env_override if follow_redirect
      @last_response
    end

    def normalize_uri(uri, params)
      uri = URI(uri)
      uri.host ||= default_domain || host
      uri.scheme ||= 'http'
      if params and uri.query
        raise InvalidArguments, "Do not send query params if url already contains them"
      end
      uri.query = URI.encode_www_form params if params
      @original_uri = URI(uri.to_s)
      if @virtual_hosts.include?(uri.host)
        uri.host = host
        uri.scheme = 'http'
      end
      URI(uri.to_s)
    end

    def prepare_headers(headers, env_override, uri)
      uri = @original_uri
      @request_env = @request_env.merge(env_override).delete_if{|k, v| v.nil? }
      h = default_headers.merge('Cookie' => HTTP::Cookie.cookie_value(@cookie_jar.cookies uri))
      if referer && (origin_uri = URI referer) &&
          (origin_uri.scheme == 'http' || uri.scheme == 'https')
        origin_uri = URI(referer)
        origin_uri.path = ''
        h['Origin'] = origin_uri.to_s
        h['Referer'] = referer
      end
      h['X-Forwarded-Proto'] = 'https' if uri.scheme == 'https'
      h['Host'] ||= uri.host
      h['Host'] ||= default_domain if default_domain
      h.merge(headers).delete_if{|k, v| v.nil? }
    end

    InfiniteRedirect = Class.new RuntimeError
    def handle_redirect(redirect_limit, env_override)
      return unless Net::HTTPRedirection === @last_response
      raise InfiniteRedirect, "Redirect loop" unless redirect_limit > 0
      @last_response = follow_redirect!(limit: redirect_limit, env_override: env_override)
    end

    def store_cookies(uri)
      return unless cookies = @last_response.get_fields('set-cookie')
      cookies.each do |cookie|
        @cookie_jar.parse cookie, uri
      end
    end
  end
end
