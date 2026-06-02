# Sonic Pi Music

SonicMyPi is a thin Ruby DSL on top of [scsynth](https://supercollider.github.io/) that plays a subset of [Sonic Pi](https://sonic-pi.net/). Most Sonic Pi songs should convert across easily.

## Install

```bash
brew install --cask sonic-pi
```

## Usage

Run a song through Sonic Pi (auto-reloads on save):

```bash
./play.rb chill1b.rb
```

Run the same song through the local Ruby DSL (no Sonic Pi GUI / daemon):

```bash
./play2.rb chill1b.rb
```

Keys (play.rb): `r` reload | `.` stop | `l` logs | `i` info | `e` errors | `q` quit

## Influences

- **Giles Bowkett / Archaeopteryx** (Ruby drum machine, ~2008). Primary aesthetic. Probabilistic beats, lambda patterns, cycling pattern shapes. The `lpattern` helper traces directly to this lineage. Bowkett targeted MIDI; this targets scsynth via OSC.
- **Monome**. Grid controller with LEDs. A row of lights scanning across the beat. Informs the desire for tracker-style or grid-style visualization later.
- **Sonic Pi** (Sam Aaron). Runtime substrate: synths, samples, `live_loop`, `with_fx`. Substrate, not aesthetic.

## Similar patterns

The pattern "swap sclang for another language, keep scsynth" is well-trodden. OSC is a stable wire protocol, so the language above scsynth is freely swappable.

| Platform     | Language    | Model                            | Note                                       |
|--------------|-------------|----------------------------------|--------------------------------------------|
| TidalCycles  | Haskell     | Cycle = measure, combinators     | Closest sibling. Targets SuperDirt → scsynth |
| Strudel      | JavaScript  | Tidal in the browser             | Same model, different host                 |
| FoxDot       | Python      | Beat-based, Player objects       | Imperative, less measure-first             |
| Overtone     | Clojure     | Direct OSC to scsynth            | Closest precedent in shape                 |
| Sonic Pi     | Ruby + Erl  | live_loop / tick                 | Current host                               |
| Glicol       | Rust        | Signal-flow + patterns           | Lower level                                |

## Goal

A lightweight runtime that dispatches a measure at a time directly to scsynth, leaving room for realtime input.
Reuses Pi's synthdefs, samples, music theory, and synth metadata.

Design choices we made along the way:

- `tick` / `look` replaced by a loop over each beat of a measure. Songs send one full measure at a time instead of note-by-note.
- `with_fx` reimplemented as a cached, song-long, single-level routing. Nested fx still pending.
- `synth_info.rb` skipped. Hand-coded `FX_MAP` for four fx covers current songs; 10k lines of Pi metadata was not worth the import cost.
- `cue` / `sync` and cross-thread `set` / `get` deferred until multi-threaded loops become necessary. The single-threaded measure-at-a-time dispatcher covers everything we do today.

Vendoring rules, for when we move Pi assets into this repo:

- Keep upstream directory layout (e.g. `vendor/sonicpi/chord.rb`).
- Mark local edits with `# SONIC_MY_PI_PATCH:` and a short reason.
- Include upstream `LICENSE` / `CREDITS` files alongside vendored content.
- Consider PR-ing harmless edits upstream.

## TODO

- See `TODO.md` for open threads.
- Watch and possibly incorporate techniques from https://www.youtube.com/watch?v=h-zTJzgz5qE.
