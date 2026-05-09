PIROOT = "/Applications/Sonic Pi.app/Contents/Resources"
SCSYNTH   = "#{PIROOT}/app/server/native/scsynth"
SYNTHDEFS = "#{PIROOT}/etc/synthdefs/compiled"
SAMPLES   = "#{PIROOT}/etc/samples"
$LOAD_PATH.unshift "#{PIROOT}/app/server/ruby/lib"

require_relative "lib/sonic_my_pi/synth"

require "sonicpi/chord"
require "sonicpi/note"
require "sonicpi/scale"

def chord(root, name)
  SonicPi::Chord.new(root, name)
end

SonicMyPi::Synth.run(synths: SYNTHDEFS, sampledir: SAMPLES) do |s|
  s.preload(:loop_amen, :ambi_choir)
  s.sync
  # ------

  # s.mesasure # will probably become a block
  s.use_bpm 120

  s.use_synth :hollow
  s.sample(:loop_amen)
  s.play chord(:a3, :major)
  s.sleep(2)
  s.play chord(:d3, :major)
  s.sleep(2)
  s.play chord(:e3, :major)

  s.sample(:ambi_choir, amp: 0.5, rate: 0.8)
  puts "playing — Ctrl-C to quit"
  sleep(3)
end
