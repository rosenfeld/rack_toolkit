# coding: utf-8
# frozen_string_literal: true

lib = File.expand_path('lib')
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require_relative 'lib/rack_toolkit/version'

Gem::Specification.new do |spec|
  spec.name          = 'rack_toolkit'
  spec.version       = RackToolkit::VERSION
  spec.authors       = ['Rodrigo Rosenfeld Rosas']
  spec.email         = ['rr.rosas@gmail.com']

  spec.summary       = %q{A dynamic Rack server and helper methods to help testing Rack apps.}
  spec.description   =
%q{This gem makes it easier to start a Puma server that will bind to a dynamic free port
by default and provide helper methods like get and post, managing sessions automatically
and using keep-alive to make the requests faster. Usually the server would be run when the
test suite starts.}
  spec.homepage      = 'https://github.com/rosenfeld/rack_toolkit'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^spec/}) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.12'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_runtime_dependency 'puma', '~> 3.5'
  spec.add_runtime_dependency 'http-cookie', '~> 1.0.2'
end
