module SonicMyPi
  # Per-synth and per-fx metadata. Sonic Pi has a 10k-line `synthinfo.rb`; this
  # is our minimal subset — same shape (lookup by symbol), just the few entries
  # our DSL actually needs. Grows row-by-row, not feature-by-feature.
  module SynthInfo
    SYNTH_ALIASES = {
      sine:     :beep,
      mod_beep: :mod_sine,
    }.freeze

    # Opt names whose values are in beats and need bpm-scaling before send.
    BEAT_SCALED_OPTS = %i[attack decay sustain release].freeze

    FX = {
      reverb:  { synthdef: "fx_reverb",  tail: 3.0 },
      lpf:     { synthdef: "fx_lpf",     tail: 0.1 },
      echo:    { synthdef: "fx_echo",    tail: 1.0 },
      flanger: { synthdef: "fx_flanger", tail: 1.0 },
    }.freeze

    module_function

    def fx(name)          = FX[name]
    def synth_alias(name) = SYNTH_ALIASES.fetch(name, name)
    def beat_scaled?(opt) = BEAT_SCALED_OPTS.include?(opt)
  end
end
