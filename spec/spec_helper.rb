require_relative '../lib/rack_toolkit'

RSpec.configure do |c|
  c.add_setting :server
  c.add_setting :skip_reset_before_example

  c.before(:suite) do
    c.server = RackToolkit::Server.new start: true
    c.skip_reset_before_example = false
  end

  c.after(:suite) do
    c.server.stop
  end

  c.before(:context){ @server = c.server }
  c.before(:example) do
    @server = c.server
    @server.reset_session! unless c.skip_reset_before_example
  end
end
