#!/usr/bin/env ruby

PIROOT    = "/Applications/Sonic Pi.app/Contents/Resources"
SYNTHDEFS = "#{PIROOT}/etc/synthdefs/compiled"
SAMPLES   = "#{PIROOT}/etc/samples"
$LOAD_PATH.unshift "#{PIROOT}/app/server/ruby/lib"

require_relative "lib/sonic_my_pi/synth"

if ARGV.empty? || ARGV[0] == "-h" || ARGV[0] == "--help"
  puts "Usage: play2.rb <file.rb>"
  puts ""
  puts "Loads the file into SonicMyPi and runs until Ctrl-C."
  exit
end

song = ARGV[0]
abort "Not found: #{song}" unless File.exist?(song)

SonicMyPi::Synth.run(synths: SYNTHDEFS, sampledir: SAMPLES) do |s|
  s.sync
  s.load_file(song)
  puts "playing #{song} — Ctrl-C to quit"
end
