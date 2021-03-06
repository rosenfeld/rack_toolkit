# RackToolkit [![Build Status](https://travis-ci.org/rosenfeld/rack_toolkit.svg?branch=master)](https://travis-ci.org/rosenfeld/rack_toolkit)

RackToolkit will launch a Puma server in an available random port (unless one is specified) and
will serve any Rack application, which can be changed dynamically. It's mostly useful for testing
Rack apps, specially when an application is a mixin of several small Rack apps. It also provides
a DSL to perform get and post requests and allows very fast integration tests with automatic
cookies based session management (using http-cookies's CookieJar).

It also supports "virtual hosts" so that you can use domain names and they would be forwarded
to the Rack app if the domain is listed in the `virtual_hosts` option. It can also simulate
https as if the request was coming from an HTTP proxy, like nginx, transparently if you use
"https://..." in the requests using the DSL.

The DSL can be also used to perform requests to other Internet domains.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rack_toolkit'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rack_toolkit

## Usage

Create a new server (the initializer supports many options, but they can be also set later):

```ruby
require 'rack_toolkit'
server = RackToolkit::Server.new start: true # or start it manually with server.start
# you can stop it with server.stop
```

Set a Rack app application and perform a request:

```ruby
server.app = ->(env){ [ 200, {}, 'success!' ] }
server.get '/'
server.last_response.code == '200'
server.last_response.body == 'success!'
```

`last_response` is a [Net::HTTPResponse](http://ruby-doc.org/stdlib/libdoc/net/http/rdoc/Net/HTTPResponse.html).

Any cookies set by the application are stored in a cookie jar (`server.cookie_jar`).
Use `server.reset_session!` to clear the session cookies jar and the referer information.

The `default_domain` is automatically appended to the `virtual_hosts` option. Here's how to use
them:

```ruby
server.virtual_hosts << 'my-domain.com' << 'www.my-domain.com'
server.default_domain = 'test-app.com' # it's appended to virtual_hosts
server.base_uri.to_s # 'http://test-app.com'
server.post 'https://test-app.com/signin', follow_redirect: false # default is true
server.env['HTTP_X_FORWARDED_PROTO'] == 'https'
server.env['HTTP_HOST'] == 'test-app.com'
server.last_response.status_code == 302 # assuming an app performing a redirect
server.current_path == '/signin'
server.follow_redirect! # not necessary if follow_redirect: false is not specified
server.current_path == '/' # assuming it has been redirected to /
server.last_response.ok? == true

server.post '/signin', params: {user: 'guest', pass: 'secret'}

server.post_data '/json_input', '{"json": "input"}'
```

Usually you'd start the server before the whole suite and replace the `app` as you test
different apps. Starting Puma is really fast (less than 5ms usually) so if you prefer
you can start it on each test file. Also, RackToolkit was designed so that you can span
multiple servers running different apps for example if you want them to communicate to each
other for testing SSO for example.

Use the `headers` param in `get`/`post`/`post_data` to override headers sent to the server.
The `env_override` param can be used to override the `env` sent to the Rack app after the
server provided its own `env`. In both cases, the resulting `headers` or `env` will be merged
with the provided options:

```ruby
server.get 'https://test-app.com/', headers: { 'Host' => 'mydomain.com' },
    env_override: { 'rack.hijack' => 'custom hijack' }
server.env['HTTP_HOST'] == 'mydomain.com'
server.env['rack.hijack'] == 'custom hijack'
```

Take a look at this project's test suite to see an example on how it can be configured and how
it works.

### Using with Rails

RackToolkit can be used with any Rack app, including Rails. Here's an example using RSpec:

```ruby
# spec/rack_spec.rb

ENV['RAILS_ENV'] = 'test'
require_relative '../config/environment.rb'
require 'rack_toolkit'

RSpec.describe 'Testing with RackToolkit' do
  server = nil
  before(:all){ server = RackToolkit::Server.new app: Rails.application, start: true }
  after(:all){ server.stop }

  it 'works' do
    server.get '/'
    expect(server.current_path).to eq '/login' # assuming root is protected with authentication
  end
end
```

### Capybara-like DSL for filling in and submitting forms...

Currently RackToolkit doesn't provide a more advanced DSL, like Capybara does, for easy access
to DOM elements, filling in forms and submitting them. At some point it could expand its DSL
to make it easier to perform such actions.

### JavaScript

JavaScript support is outside the scope of this project unless we can think of some way of
adding it without requiring a real browser (headless or not) which adds a significant overhead
and RackToolkit main goal is to remain fast. I don't think it will even happen. If you want
to test your JavaScript, please do so with Capybara or using a separate JavaScript test runner,
testing it in isolation with the server-side, which should be quite fast.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec`
to run the tests. You can also run `bin/console` for an interactive prompt that will allow
you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a
new version, update the version number in `version.rb`, and then run `bundle exec rake release`,
which will create a git tag for the version, push git commits and tags, and push the `.gem`
file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome [on GitHub](https://github.com/rosenfeld/rack_toolkit).


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

