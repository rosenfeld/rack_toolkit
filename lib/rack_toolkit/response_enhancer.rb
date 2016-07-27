# frozen_string_literal: true
require 'net/http'

module RackToolkit
  class Server
    module ResponseEnhancer
      def status_code
        @status_code ||= code.to_i
      end

      def ok?
        code == '200'
      end

      def redirect?
        Net::HTTPRedirection === self
      end

      def error?
        !(ok? || redirect?)
      end

      def headers
        @headers ||= to_hash
      end
    end
  end
end
