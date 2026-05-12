require "simplecov"
require "simplecov_json_formatter"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/test/"
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::JSONFormatter,
  ])
end

require "minitest/autorun"
require "minitest/spec"

require_relative "../lib/sonic_my_pi/synth"

# Records every OSC packet handed to it. Use in place of OSC::Client.
class FakeClient
  attr_reader :sent

  def initialize
    @sent = []
  end

  def send(packet)
    @sent << packet
  end
end
