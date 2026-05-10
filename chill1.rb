# Chill Trance for Concentration v2
# Style: Progressive / Melodic Chill
# BPM: 120 (Relaxed but steady)
# this was genereated by Gemni. but feel we can do more here.
# TODO: follow up https://beatstorapon.com/blog/the-definitive-guide-to-hip-hop-beatmaking-basics-to-pro-level/

use_bpm 120

# exponential backoff
# 0 = no change, 15 = lots of change, 14 = most probable, a/10 = 50%, 2 = rare
PROBS = [0, 0.01, 0.03, 0.06, 0.1, 0.15, 0.22, 0.3, 0.38, 0.45, 0.5, 0.65, 0.8, 0.9, 0.96, 1.0].freeze

# return true on a given beat (typically 0)
def on_beat(*num)
  mod = num[0] < 0 ? - num.shift : 16 # assume 16 16ths/measure. start with negative to change beats/measure
  num.include?(look % mod)
end

# on a given beat (typically 0) choose a different pattern
def on_beat_choose(beat, name, patterns)
  #on beat will lookup a different pattern number
  val = on_beat(beat) ? set(name, rrand_i(0, patterns.length - 1)).tap {|x| puts "choose #{x}" } : get(name)

  # return that pattern
  patterns[val]
end

# convert
# params: ordered key -> translation table to fetch from the pattern
def xpattern(params, pattern)
  pattern = pattern.split if pattern.kind_of?(String)
  pattern.map do |p|
    params.zip(p.chars).each_with_object({}) do |((key, tran), v), h|
      h[key] = tran.kind_of?(Array) ? tran[v.hex] : tran[v]
    end
  end
end

# probability pattern per beat (4/4 w/ tick every 1/16 note)
# 0 = 0%, f = 100%, a = 50%
# str2: fill pattern repeated to pad to 16 steps
def lpattern(str, str2 = str)
  pattern = str.split
  need = 16 - pattern.size
  if need > 0
    str2 = str2.split
    pattern += str2 * (need / str2.size).round
  end
  pattern = pattern.map { |l| PROBS[l.hex] }
  -> { pattern[look % 16] > rand }
end


kick_patterns=[
  lpattern("f f f 0"),
  lpattern("f 0 f 0 f 0 0 0", "1 0 0 0"),
  lpattern("f 0 0 0 f 0 0 0 f 0 f 0 f 0 0 0"),
  lpattern("f 0 f 0", "f 0 0 0"),
  lpattern("f 1 3 1", "f 0 0 0"),
]


# 1. SOFT PULSE: A muted kick for a steady rhythm without being jarring
live_loop :soft_kick do
  tick
  is_kick = on_beat_choose(0, :current_kick, kick_patterns).call
  sample :bd_tek, amp: 1.2, cutoff: 90 if is_kick
  sleep 0.25
end

# 2. AMBIENT TEXTURE: Shifting, airy pads
live_loop :chill_pads do
  use_synth :hollow # A very soft, airy sound
  with_fx :reverb, room: 0.9, mix: 0.7 do
    # A calm minor 7th chord progression
    notes = (ring chord(:a3, :m7), chord(:f3, :major7), chord(:c3, :major7), chord(:g3, :major7))
    play notes.tick, attack: 4, release: 6, amp: 0.5
    sleep 8
  end
end

# 3. SUBTLE BASS: A deep, smooth sine wave to fill the low end
# think we could have more fun here (throw in 16th and 32nds)
live_loop :sub_bass do
  use_synth :sine
  # Syncs with the kick but adds a slight "off-beat" feel (much lighter)
  play :a1, release: 0.5, amp: 0.6  # 1/8 notes 1
  sleep 0.5
  play :a1, release: 0.2, amp: 0.3 # 1/8 notes and
  sleep 0.5
end

# 4. MELODIC SPARKLE: A slow, "wet" arpeggio for focus
live_loop :glimmer do
  use_synth :dtri
  with_fx :echo, phase: 0.75, decay: 6, mix: 0.4 do
    with_fx :reverb, mix: 0.5 do
      # Randomly picks notes from a scale to keep it from feeling too repetitive
      play scale(:a3, :minor_pentatonic).choose, release: 0.1, amp: 0.2, pan: rrand(-0.8, 0.8)
      sleep [0.25, 0.5, 1].choose
    end
  end
end

# 5. PERCUSSION: Subtle "white noise" hats to maintain momentum
live_loop :percussion do
  sample :elec_soft_kick, amp: 0.2, rate: 2 if spread(3, 8).tick
  sample :elec_fuzz_tom, amp: 0.1, rate: 0.5 if one_in(4)
  sleep 0.25
end
