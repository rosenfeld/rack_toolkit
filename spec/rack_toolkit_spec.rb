# frozen_string_literal: true

require_relative '../lib/rack_toolkit'
require_relative 'spec_helper'
require 'cgi'

RSpec.describe RackToolkit do
  it 'returns 500 status code when no app is defined' do
    @server.app = nil
    expect(@server.get('/').code).to eq '500'
  end

  it 'supports requesting from external urls', external: true do
    expect(@server.get('http://www.google.com', follow_redirect: true).code).to eq '200'
  end

  context 'with sample app' do
    before(:all) { @server.app = ->(env) { [200, {}, ['success!']] } }

    it 'supports overriding the Rack app' do
      @server.get('/')
      expect(@server.last_response.code).to eq '200'
      expect(@server.last_response.body).to eq 'success!'
    end

    it 'supports accessing through a default domain' do
      @server.default_domain = 'test-app.com'
      @server.get('/')
      expect(@server.env['HTTP_HOST']).to eq 'test-app.com'
      expect(@server.env.key? 'HTTP_X_FORWARDED_PROTO').to be false
    end

    it 'allows simulating an https request' do
      @server.default_domain = 'test-app.com'
      @server.get('https://test-app.com/login')
      expect(@server.env.key? 'HTTP_REFERER').to be false
      expect(@server.env['HTTP_HOST']).to eq 'test-app.com'
      expect(@server.env['HTTP_X_FORWARDED_PROTO']).to eq 'https'
      @server.get('https://test-app.com')
      expect(@server.env['HTTP_REFERER']).to eq 'https://test-app.com/login'
      expect(@server.env['HTTP_ORIGIN']).to eq 'https://test-app.com'
    end

    it 'always set up host' do
      @server.default_domain = nil
      @server.get '/'
      expect(@server.env['HTTP_HOST']).to eq '127.0.0.1'
    end

    it 'allows headers to be specified' do
      @server.get '/', headers: {'Host' => 'overriden.com'}
      expect(@server.env['HTTP_HOST']).to eq 'overriden.com'
    end

    it 'allows overriding the env sent to the app' do
      @server.get '/'
      expect(@server.env['rack.hijack']).to respond_to :call
      @server.get '/', env_override: {'rack.hijack' => 'overriden'}
      expect(@server.env['rack.hijack']).to eq 'overriden'
    end
  end

  context 'with redirect' do
    before(:all) do
      root = @server.base_uri.to_s
      @server.app = ->(env) do
        case env['PATH_INFO']
        when '/redirect_permanent' then [301, {'location' => root}, ['redirecting']]
        when '/redirect' then [302, {'location' => root}, ['redirecting']]
        when '/redirect_loop' then [302, {'location' => root + '/redirect_loop'}, []]
        else
          [200, {}, ['redirected']]
        end
      end
    end

    it 'follows redirect by default' do
      @server.get '/redirect'
      expect(@server.last_response.code).to eq '200'
      expect(@server.last_response.body).to eq 'redirected'
      @server.get '/redirect_permanent'
      expect(@server.last_response.code).to eq '200'
      expect(@server.last_response.body).to eq 'redirected'
    end

    it 'allows to change the default behavior to not redirect' do
      @server.get '/redirect', follow_redirect: false
      expect(@server.last_response.code).to eq '302'
      expect(@server.last_response.body).to eq 'redirecting'
    end

    it 'raises on infinite loop' do
      expect{ @server.get '/redirect_loop' }.
        to raise_exception(RackToolkit::Server::InfiniteRedirect)
    end
  end

  context 'with cookies' do
    before(:all) do
      root = @server.base_uri.to_s
      cookie = "id=123; path=/; domain=#{@server.host}; httponly"
      @server.app = ->(env) do
        case env['PATH_INFO']
        when '/signin'
          if env['QUERY_STRING'] == 'pass=xyz' && env['rack.input'].read == 'pass=xyz'
            [302, {'Location' => root, 'Set-Cookie' => cookie}, []]
          else
            [200, {}, ['invalid pass code']]
          end
        else
          cookies = CGI::Cookie.parse env['HTTP_COOKIE'].to_s
          if (c = cookies['id']) && c[0] == '123'
            [200, {}, ['authorized']]
          else
            [403, {}, ['forbidden']]
          end
        end
      end
    end

    it 'keeps a cookies based session' do
      @server.get '/'
      expect(@server.last_response.code).to eq '403'
      @server.post '/signin', params: {pass: 'xyz'}, query_params: {user: 'guest'}
      expect(@server.last_response.code).to eq '200'
      @server.reset_session!
      @server.get '/'
      expect(@server.last_response.code).to eq '403'
    end
  end

  it 'allows to post non-form data too' do
    @server.app = ->(env){ [200, {}, [env['rack.input'].read]] }
    @server.post_data '/', 'posted data'
    expect(@server.last_response.body).to eq 'posted data'
  end

  context 'with virtual hosts' do
    before(:all) do
      @server.virtual_hosts << 'abc.com' << 'great.com.br'
      @server.default_domain = 'awesome.org'
      @server.app = ->(env){[200, {}, [env['HTTP_HOST']]]}
    end

    it 'uses default_domain when available for paths requests' do
      expect(@server.get('/').body).to eq 'awesome.org'
    end

    it 'allows other any domains in virtual hosts' do
      ['abc.com', 'great.com.br', 'awesome.org'].each do |host|
        expect(@server.get("http://#{host}").body).to eq host
      end
    end
  end
end
