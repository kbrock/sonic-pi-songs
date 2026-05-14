PIROOT    = "/Applications/Sonic Pi.app/Contents/Resources"
SCSYNTH   = "#{PIROOT}/app/server/native/scsynth"
SYNTHDEFS = "#{PIROOT}/etc/synthdefs/compiled"
SAMPLES   = "#{PIROOT}/etc/samples"
$LOAD_PATH.unshift "#{PIROOT}/app/server/ruby/lib"

require_relative "lib/sonic_my_pi/synth"

# probability per beat — exponential-ish curve, keyed by hex digit
# 0 = 0%, f = 100%, a ≈ 50%
PROBS = [0, 0.01, 0.03, 0.06, 0.1, 0.15, 0.22, 0.3, 0.38, 0.45, 0.5, 0.65, 0.8, 0.9, 0.96, 1.0].freeze

def lpattern(str, str2 = str)
  pattern = str.split
  need = 16 - pattern.size
  if need > 0
    str2 = str2.split
    pattern += str2 * (need / str2.size).round
  end
  pattern = pattern.map { |l| PROBS[l.hex] }
  ->(x) { pattern[x % 16] > rand }
end

KICK_PATTERNS = [
  lpattern("f f f 0"),
  lpattern("f 0 f 0 f 0 0 0", "1 0 0 0"),
  lpattern("f 0 0 0 f 0 0 0 f 0 f 0 f 0 0 0"),
  lpattern("f 0 f 0", "f 0 0 0"),
  lpattern("f 1 3 1", "f 0 0 0"),
]
HAT_PATTERNS = [lpattern("f 0 0 f 0 0 f 0")]

SonicMyPi::Synth.run(synths: SYNTHDEFS, sampledir: SAMPLES) do |s|
  s.preload(:bd_tek, :elec_soft_kick, :elec_fuzz_tom)
  s.sync

  s.use_bpm 120

  # 1. SOFT PULSE — muted kick, pattern reshuffles every bar
  s.live_loop :soft_kick do |s|
    current_beat = s.choose(KICK_PATTERNS)
    16.times do |i|
      s.sample :bd_tek, amp: 1.2, cutoff: 90 if current_beat.call(i)
      s.sleep 0.25
    end
  end

  # 2. AMBIENT TEXTURE — slow chord progression
  s.live_loop :chill_pads do |s|
    s.use_synth :hollow
    s.with_fx :reverb, room: 0.9, mix: 0.7 do
      [s.chord(:a3, :m7), s.chord(:f3, :major7), s.chord(:c3, :major7), s.chord(:g3, :major7)].each do |c|
        s.play c, attack: 4, release: 6, amp: 0.5
        s.sleep 8
      end
    end
  end

  # 3. SUBTLE BASS — eighth-note pulse
  s.live_loop :sub_bass do |s|
    s.use_synth :sine
    s.play :a1, release: 0.5, amp: 0.6
    s.sleep 0.5
    s.play :a1, release: 0.2, amp: 0.3
    s.sleep 0.5
  end

  # 4. MELODIC SPARKLE — random scale notes, no fx
  s.live_loop :glimmer do |s|
    s.use_synth :dtri
    s.play s.choose(s.scale(:a3, :minor_pentatonic)), release: 0.1, amp: 0.2, pan: s.rrand(-0.8, 0.8)
    s.sleep s.choose([0.25, 0.5, 1])
  end

  # 5. PERCUSSION — euclidean hats + occasional tom
  s.live_loop :percussion do |s|
    hat = s.choose(HAT_PATTERNS)
    16.times do |i|
      s.sample :elec_soft_kick, amp: 0.2, rate: 2 if hat.call(i)
      s.sample :elec_fuzz_tom,  amp: 0.1, rate: 0.5 if s.one_in(4)
      s.sleep 0.25
    end
  end

  puts "playing — Ctrl-C to quit"
end
