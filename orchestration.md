# Orchestration paradigms

Four ways to compose a song in this DSL, ordered by increasing coordination cost. Pick the smallest one that expresses what the song needs.

| # | Paradigm                         | Threads | Conductor | Coordination       |
|---|----------------------------------|---------|-----------|--------------------|
| 1 | Linear timeline                  | 1       | implicit  | none (serial)      |
| 2 | Parallel live_loops              | N       | none      | none (independent) |
| 3 | Conductor + shared state         | N+1     | yes       | `set` / `get`      |
| 4 | Event-driven (cue/sync)          | N+1     | optional  | `cue` / `sync`     |

---

## 1. Linear timeline

One block. `play` and `sleep` interleave on a single offset. No threads.

```ruby
SonicMyPi::Synth.run(synths: SYNTHDEFS) do
  use_synth :hollow

  [chord(:a3, :m7), chord(:d3, :m7), chord(:e3, :m7), chord(:a3, :m7)].each do |c|
    play c, attack: 0.5, release: 3
    sleep 4
  end

  16.times do |i|
    sample :bd_haus if [1,0,0,0, 1,0,1,0, 1,0,0,0, 1,0,1,1][i] == 1
    sample :elec_hi_snare if i == 4 || i == 12
    sleep 0.25
  end
end
```

Use when: the song is short and parts naturally interleave. Adding a third part starts to hurt.

---

## 2. Parallel live_loops

Each part is its own loop with its own offset. All anchored to the same `@t0`. No communication between parts.

```ruby
SonicMyPi::Synth.run(synths: SYNTHDEFS) do
  live_loop :drums do
    16.times do |i|
      sample :bd_haus if [1,0,0,0, 1,0,1,0, 1,0,0,0, 1,0,1,1][i] == 1
      sleep 0.25
    end
  end

  live_loop :bass do
    use_synth :fm
    [40, 40, 43, 45].each do |n|
      play n, release: 0.8
      sleep 1
    end
  end

  live_loop :pad do
    use_synth :hollow
    [chord(:a3, :m7), chord(:d3, :m7), chord(:e3, :m7), chord(:a3, :m7)].each do |c|
      play c, attack: 1, release: 4, amp: 0.4
      sleep 4
    end
  end
end
```

Use when: parts are independent and the song is one section throughout. No structure that one part needs to react to.

---

## 3. Conductor + shared state

A silent conductor publishes song-structural state (`section`, `current_chord`, `intensity`). Performer loops read state each iteration and play accordingly. Loose coupling — performers don't block on the conductor.

```ruby
SECTIONS = [
  { name: :intro,  bars: 4 },
  { name: :verse,  bars: 8 },
  { name: :chorus, bars: 4 },
  { name: :verse,  bars: 4 },
  { name: :chorus, bars: 4 },
  { name: :bridge, bars: 4 },
  { name: :chorus, bars: 4 },
  { name: :chorus, bars: 4 },
]

PROGRESSION = {
  intro:  [chord(:a3, :m7)],
  verse:  [chord(:a3, :m7), chord(:d3, :m7)],
  chorus: [chord(:f3, :major7), chord(:c3, :major7), chord(:g3, :major7), chord(:a3, :m7)],
  bridge: [chord(:e3, :m7), chord(:b3, :m7)],
}

SonicMyPi::Synth.run(synths: SYNTHDEFS) do
  live_loop :conductor do
    SECTIONS.each do |s|
      s[:bars].times do |bar|
        set :section,     s[:name]
        set :section_bar, bar
        set :chord,       PROGRESSION[s[:name]][bar % PROGRESSION[s[:name]].length]
        sleep 4
      end
    end
    stop
  end

  live_loop :pad do
    use_synth :hollow
    play get(:chord), attack: 1, release: 4, amp: 0.4
    sleep 4
  end

  live_loop :drums do
    pattern = case get(:section)
              when :intro,  :bridge then [1,0,0,0, 1,0,0,0]
              when :verse           then [1,0,0,0, 1,0,1,0]
              when :chorus          then [1,0,1,0, 1,0,1,1]
              end
    pattern.each { |hit| sample :bd_haus if hit == 1; sleep 0.5 }
  end

  live_loop :bass do
    root = get(:chord).first - 12
    play root, release: 0.8 if get(:section) != :intro
    sleep 1
  end
end
```

Use when: song has structure (intro / verse / chorus / bridge) and parts need to know "where are we." Adding a section is one entry in `SECTIONS`; muting a part in a section is one branch.

---

## 4. Event-driven (cue / sync)

Tight coordination: producer threads `cue` named events, consumer threads `sync` to block until the event fires. Useful for transitions and fills that must hit *exactly* on a downbeat. Reactive threads have no clock of their own.

```ruby
SonicMyPi::Synth.run(synths: SYNTHDEFS) do
  live_loop :conductor do
    SECTIONS.each do |s|
      set :section, s[:name]
      cue  :section_start
      s[:bars].times do |bar|
        cue :downbeat
        sleep 4
      end
    end
    cue :song_end
  end

  live_loop :drums do
    sync :downbeat
    pattern = drum_pattern_for(get :section)
    pattern.each { |hit| sample :bd_haus if hit == 1; sleep 0.25 }
  end

  live_loop :fill_picker do
    sync :downbeat
    if rrand < 0.1
      cue :do_fill
    end
  end

  live_loop :fills do
    sync :do_fill
    4.times { sample :elec_hi_snare; sleep 0.125 }
  end

  live_loop :transition_swell do
    sync :section_start
    use_synth :dark_ambience
    play chord(:a3, :m7), attack: 2, release: 4, amp: 0.6
  end
end
```

Use when: things must happen *on* an event (downbeat hit, section boundary, external trigger), not "next time my loop comes around." Also when threads are purely reactive — no clock of their own.

---

## Combining

These compose. A real song typically uses #2 for steady parts, #3 for structural state, and #4 for tight transitions:

```ruby
SonicMyPi::Synth.run(synths: SYNTHDEFS) do
  live_loop :conductor do          # #3 — sets section state + #4 — cues transitions
    SECTIONS.each do |s|
      set :section, s[:name]
      cue :section_start
      s[:bars].times { sleep 4 }
    end
  end

  live_loop :drums do              # #3 — reads section, runs its own clock
    pattern = drum_pattern_for(get :section)
    pattern.each { |hit| sample :bd_haus if hit == 1; sleep 0.25 }
  end

  live_loop :riser do              # #4 — purely reactive
    sync :section_start
    sample :ambi_swoosh if get(:section) == :chorus
  end
end
```

The runtime primitive count stays small: `play`, `sample`, `sleep`, `live_loop`, `set`, `get`, `cue`, `sync`. Everything above is library or user code.
