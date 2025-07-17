# frozen_string_literal: true

require "stringio"
require "open-uri" # For OpenURI::HTTPError
require "systemu"
require_relative "inventory"

module Narou
  module Wget
    # A StringIO-like object that mimics the object returned by open-uri.
    class WgetIO < StringIO
      attr_reader :meta, :status

      def initialize(initial_string = "", meta = {}, status = [])
        super(initial_string)
        @meta = meta
        @status = status
      end

      def base_uri
        # This is a simplification. Real redirection handling is more complex.
        # wget follows redirections by default. The last Location is what we want.
        # But parsing it from stderr is tricky. Let's just return the original uri.
        @meta["uri"]
      end
    end

    def self.open(uri, *rest, &block)
      options = rest.find { |arg| arg.is_a?(Hash) } || {}

      ua = Inventory.load("local_setting")["user-agent"] || "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"

      # Build wget command
      cmd_headers = []
      # Default headers from user's prompt
      cmd_headers << %'--header="User-Agent: #{ua}"'
      cmd_headers << %'--header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"'
      cmd_headers << %'--header="Accept-Language: en-US,en;q=0.5"'
      cmd_headers << %'--header="Accept-Encoding: gzip, deflate"'
      cmd_headers << %'--header="Accept-Charset: utf-8"'
      cmd_headers << %'--header="Connection: keep-alive"'

      # Headers from options hash
      options.each do |key, value|
        next unless key.is_a?(String)
        cmd_headers << %'--header="#{key}: #{value}"'
      end

      command = %'wget --server-response --compression=auto -O - #{cmd_headers.join(" ")} "#{uri}"'

      status, stdout, stderr = systemu(command)

      unless status.success?
        if stderr =~ /(\d{3}) (Not Found|Forbidden|Error)/
          raise OpenURI::HTTPError.new("#{status.exitstatus} #{$2}", nil)
        else
          raise OpenURI::HTTPError.new("wget command failed: #{stderr.strip}", nil)
        end
      end

      # Parse headers from stderr
      response_headers = {}
      status_line = []
      # The last header block in stderr is the one for the final response
      last_header_block = stderr.split(/(\r\n\r\n|\n\n)/).select{|s| s.start_with?("  HTTP/")}.last || ""
      last_header_block.each_line do |line|
        if line.strip.start_with?("HTTP/")
          _http, code, msg = line.strip.split(" ", 3)
          status_line = [code, msg]
        elsif line =~ /^\s*([^:]+):\s*(.+)$/
          response_headers[$1.downcase] = $2.strip
        end
      end

      io = WgetIO.new(stdout, response_headers, status_line)
      io.meta["uri"] = uri # Store original URI

      if block_given?
        begin
          yield io
        ensure
          # StringIO doesn't need closing, but for compatibility.
        end
      else
        return io
      end
    end
  end
end
