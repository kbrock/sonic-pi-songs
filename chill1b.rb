# Chill Trance v3 — DSL-target shape
#
# Runs unchanged in Sonic Pi. The named primitives below are what our DSL
# needs to support for parity:
#
#   use_bpm, use_synth, play, sample, sleep
#   chord, scale
#   live_loop, tick, look
#   set, get
#   with_fx (no-op in v1)
#   rrand, rrand_i, choose, one_in, spread, ring

use_bpm 120

# probability per beat — exponential-ish curve, keyed by hex digit
# 0 = 0%, f = 100%, a ≈ 50%
PROBS = [0, 0.01, 0.03, 0.06, 0.1, 0.15, 0.22, 0.3, 0.38, 0.45, 0.5, 0.65, 0.8, 0.9, 0.96, 1.0].freeze

# true on a given beat (typically 0). negative first arg overrides default 16 steps/measure.
def on_beat(*num)
  mod = num[0] < 0 ? -num.shift : 16
  num.include?(look % mod)
end

# every `beat` steps, pick a random pattern; otherwise return last pick.
# uses set/get to remember the choice across calls.
def on_beat_choose(beat, name, patterns)
  val = on_beat(beat) ? set(name, rrand_i(0, patterns.length - 1)) : get(name)
  patterns[val]
end

# probability pattern over 16 steps (4/4, 16th-note grid).
# str:  primary pattern (space-separated hex)
# str2: pad pattern (repeated to fill 16 if str is shorter)
# returns a lambda that, when called, rolls the dice for the current step.
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

KICK_PATTERNS = [
  lpattern("f f f 0"),
  lpattern("f 0 f 0 f 0 0 0", "1 0 0 0"),
  lpattern("f 0 0 0 f 0 0 0 f 0 f 0 f 0 0 0"),
  lpattern("f 0 f 0", "f 0 0 0"),
  lpattern("f 1 3 1", "f 0 0 0"),
]

# 1. SOFT PULSE — muted kick, pattern reshuffles every downbeat
live_loop :soft_kick do
  tick
  is_kick = on_beat_choose(0, :current_kick, KICK_PATTERNS).call
  sample :bd_tek, amp: 1.2, cutoff: 90 if is_kick
  sleep 0.25
end

# 2. AMBIENT TEXTURE — slow chord progression
live_loop :chill_pads do
  use_synth :hollow
  with_fx :reverb, room: 0.9, mix: 0.7 do
    [chord(:a3, :m7), chord(:f3, :major7), chord(:c3, :major7), chord(:g3, :major7)].each do |c|
      play c, attack: 4, release: 6, amp: 0.5
      sleep 8
    end
  end
end

# 3. SUBTLE BASS — eighth-note pulse
live_loop :sub_bass do
  use_synth :sine
  play :a1, release: 0.5, amp: 0.6
  sleep 0.5
  play :a1, release: 0.2, amp: 0.3
  sleep 0.5
end

# 4. MELODIC SPARKLE — random scale notes, no fx
live_loop :glimmer do
  use_synth :dtri
  play scale(:a3, :minor_pentatonic).choose, release: 0.1, amp: 0.2, pan: rrand(-0.8, 0.8)
  sleep [0.25, 0.5, 1].choose
end

# 5. PERCUSSION — euclidean hats + occasional tom
live_loop :percussion do
  sample :elec_soft_kick, amp: 0.2, rate: 2 if spread(3, 8).tick
  sample :elec_fuzz_tom,  amp: 0.1, rate: 0.5 if one_in(4)
  sleep 0.25
end
