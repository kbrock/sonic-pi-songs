# play2-port

List what to change in a Sonic Pi `.rb` file so it runs on this project's
`play2.rb` runtime. Read the file at `$ARGUMENTS`. Compare against play2's
DSL surface (`lib/sonic_my_pi/synth.rb` and `lib/sonic_my_pi/util.rb`).

For each line that uses a Sonic Pi primitive play2 doesn't support, output:
- the line number
- the construct
- a one-line replacement

Group by primitive, not by line, so the reader sees the conversion pattern
once. Don't modify the file — listing only.

## Supported in play2 (leave alone)

`use_bpm`, `use_synth`, `play`, `sample`, `sleep`, `chord`, `scale`,
`live_loop`, `with_fx` (nestable), `rrand`, `rrand_i`, `choose`, `one_in`.

## Known incompatibilities

| Sonic Pi | play2 replacement | Note |
|----------|-------------------|------|
| `tick` | wrap the live_loop body in `16.times do \|i\|` (or `16.times.map { \|i\| ... }` when collecting). Pass `i` where `tick` was used. For a lambda stored in an array, call it with the step: `pattern.call(i)` | per-thread counter; play2 has no thread-local state |
| `look` | take the step as a lambda parameter: `-> (i) { pattern[i % 16] > rand }`. Caller passes `i` (see `tick` row) | same root cause |
| `(ring x, y, z)` | plain Ruby array `[x, y, z]` | rings are a Sonic Pi type |
| `arr.tick` | iterate `arr.each do \|item\|` *inside* the live_loop body, OR capture an index in a closure outside the loop and increment per iteration | each-form runs the whole sequence per live_loop iteration; closure-form preserves chill2-style "one note per iteration" timing |
| `arr.choose` | `choose(arr)` | play2 has the function, not the monkey-patch |
| `set(:k, v)` / `get(:k)` | not supported — restate state inline or via closure | cross-thread state; play2 is single-threaded |
| `on_beat(...)` / `on_beat_choose(...)` | not supported — restructure to iterate explicitly with `N.times do \|i\|` and choose the pattern at the top of the live_loop body | depends on `tick`/`look`/`set`/`get` |
| `spread(n, m).tick` | precompute the euclidean pattern as a hex string and use the file's `lpattern` helper | euclidean rhythm — no play2 equivalent |
| Lambda `-> { ... look ... }` | take the step as a parameter: `-> (i) { ... i ... }` | call sites pass the step |
| Local var with `kick_patterns =` inside file scope | uppercase + `.freeze` (`KICK_PATTERNS`) | matches the pattern other ported songs use; keeps top-level data immutable |

## After listing

Pause for the user to confirm before any file conversion happens. If a
construct in the file isn't covered by the table above, call it out as
"unhandled — please advise" so we can grow the table.
