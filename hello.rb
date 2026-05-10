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
  s.preload(:loop_amen, :ambi_choir, :bd_haus, :elec_hi_snare)
  s.sync
  # ------

  s.use_bpm 120
  start = s.offset

  # layer 1: chord pad (with_fx no-op in v1 — kept for interface parity)
  s.use_synth :hollow
  s.with_fx :reverb, room: 0.9, mix: 0.7 do
    [chord(:a3, :m7), chord(:d3, :m7), chord(:e3, :m7), chord(:a3, :m7)].each do |c|
      s.play c, attack: 1, release: 4, amp: 0.5
      s.sleep 4
    end
  end

  # layer 2: kick under the pad — rewind offset to start
  s.offset = start
  16.times do
    s.sample :bd_haus, amp: 0.7
    s.sleep 1
  end

  # layer 3: bass under the kick
  s.offset = start
  s.use_synth :sine
  16.times do |i|
    s.play [33, 33, 38, 40][i / 4], release: 0.4, amp: 0.5  # roots: A1 A1 D2 E2
    s.sleep 1
  end

  # layer 4: snare on 2 and 4 of each bar
  s.offset = start
  16.times do |i|
    s.sample :elec_hi_snare, amp: 0.4 if i % 4 == 2
    s.sleep 1
  end

  # layer 5: still keep the original ambient touch at the very end
  s.offset = start + 14
  s.sample :ambi_choir, amp: 0.4, rate: 0.8

  puts "playing — Ctrl-C to quit"
  sleep(20)
end
