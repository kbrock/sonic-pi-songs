# Runtime mechanisms

Three runtime models, smallest to largest. Same DSL surface; different mechanism underneath. Same code shape on the user's side — but how/when threads sleep and wake is what changes.

---

## 1. Single linear loop (today)

One thread. One `@offset`. The user's block runs in milliseconds, queueing OSC bundles stamped with future NTP timestamps. **scsynth** holds them and fires them at the right wall-clock moment — Ruby has nothing more to do.

```ruby
@t0     = Time.now + 0.05
@offset = 0

def play(notes, **opts)
  @client.send(OSC::Bundle.new(@t0 + @offset, message))
end

def sleep(dt)
  @offset += dt          # logical: advances bundle timestamps, not wall-clock
end

# user block runs to completion immediately.
# then:
Kernel.sleep              # keep Ruby process alive; scsynth fires queued events.
```

| Aspect       | How                                                          |
|--------------|--------------------------------------------------------------|
| Wakeup       | none                                                          |
| Sleep        | only the trailing `Kernel.sleep` to keep the process alive    |
| Thread-local | n/a — one thread                                              |
| Scheduling   | scsynth (timetag in OSC bundle)                               |

---

## 2. Single-threaded scheduler, N live_loops

Still one OS thread. Each `live_loop` is a stored `(block, offset)` pair. A dispatcher loop picks the loop whose next iteration is due soonest and runs one body of it.

```ruby
@loops    = {}                   # name => { block:, offset: 0 }
LOOKAHEAD = 0.2

def live_loop(name, &block)
  @loops[name] = { block: block, offset: 0 }
end

def run!
  loop do
    ready = @loops.values.select { |l| l[:offset] < (Time.now - @t0) + LOOKAHEAD }
    if ready.empty?
      next_at = @t0 + @loops.values.map { |l| l[:offset] }.min - LOOKAHEAD
      Kernel.sleep([next_at - Time.now, 0.001].max)
    else
      ready.each do |l|
        @offset = l[:offset]      # restore this loop's clock
        l[:block].call            # body fires bundles, advances @offset via sleep
        l[:offset] = @offset      # save back
      end
    end
  end
end
```

| Aspect       | How                                                                                |
|--------------|------------------------------------------------------------------------------------|
| Wakeup       | dispatcher's `Kernel.sleep` ends when next loop is due                             |
| Sleep        | `Kernel.sleep(next_at - now)` between dispatch passes                              |
| Thread-local | none — `l[:offset]` is per-loop state in a shared Hash; dispatcher swaps `@offset` |
| set / get    | plain `@state[key] = ...`; `@state[key]`. No mutex needed (one thread)             |
| cue / sync   | a flag in `@state`, checked at iteration boundaries. No real blocking              |

---

## 3. Multi-threaded live_loops

Each `live_loop` is an OS Thread. State that was `l[:offset]` in model 2 becomes `Thread.current[:offset]`. Cross-thread coordination needs real primitives.

```ruby
@state  = Concurrent::Map.new    # set/get backing store
@cue_mu = Hash.new { |h, k| h[k] = Mutex.new }
@cues   = Hash.new { |h, k| h[k] = ConditionVariable.new }

def live_loop(name, &block)
  Thread.new do
    Thread.current[:offset] = 0
    Thread.current[:synth]  = :hollow
    Thread.current[:rng]    = Random.new(seed_for(name))
    loop do
      block.call                 # fires bundles, advances :offset
      wait_until(@t0 + Thread.current[:offset] - LOOKAHEAD)
    end
  end
end

def wait_until(t)
  delta = t - Time.now
  Kernel.sleep(delta) if delta > 0
end

def play(notes, **opts)
  ts = @t0 + Thread.current[:offset]
  @client.send(OSC::Bundle.new(ts, message))
end

def sleep(dt)
  Thread.current[:offset] += dt
end

def set(key, value) = @state[key] = value
def get(key)        = @state[key]

def cue(name)
  @cue_mu[name].synchronize { @cues[name].broadcast }     # wake every sync waiting on :name
end

def sync(name)
  @cue_mu[name].synchronize { @cues[name].wait(@cue_mu[name]) }   # block until broadcast
end
```

| Aspect          | How                                                                              |
|-----------------|----------------------------------------------------------------------------------|
| Wakeup (timed)  | each thread `Kernel.sleep`s until its own `@t0 + offset - LOOKAHEAD`              |
| Wakeup (event)  | thread blocked in `cv.wait`; another thread's `cv.broadcast` releases it         |
| Sleep           | `Kernel.sleep(delta)` per thread, independent                                     |
| Thread-local    | `:offset`, `:synth`, `:rng` — one set per live_loop, no save/restore needed       |
| set / get       | `Concurrent::Map[key] =` / `[key]` — atomic, lock-free                            |
| cue / sync      | `Mutex` + `ConditionVariable.broadcast` / `.wait`                                 |

---

## Mechanism cheat sheet

| Operation          | Underlying call                                       |
|--------------------|-------------------------------------------------------|
| `play`, `sample`   | `client.send(OSC::Bundle.new(timestamp, msg))`        |
| `sleep dt`         | `Thread.current[:offset] += dt` (no OS sleep)         |
| Time-loop wakeup   | `Kernel.sleep(t0 + offset - LOOKAHEAD - now)`         |
| `set k, v`         | `@state[k] = v` (Concurrent::Map)                     |
| `get k`            | `@state[k]`                                            |
| `cue :k`           | `@cues[:k].broadcast` (wake every waiter)              |
| `sync :k`          | `@cues[:k].wait(mutex)` (release+block, reacquire)     |

A `cue` with no waiters is a no-op (broadcast wakes no one). A `sync` with no prior cue blocks indefinitely — caller must already be running when the cue fires.

---

## How it feels working together

- **Time-driving threads**: each one is a tight `play; sleep; play; sleep; loop` body. Between iterations they `Kernel.sleep` until their own next horizon. They never see each other directly — they meet only in scsynth, where their bundles share an NTP timeline.
- **Event-driven threads**: blocked on `cv.wait`. Wake on `broadcast`, do their work, block again. They consume CPU only when something happens.
- **Conductor (if any)**: a regular time-driving thread whose body is mostly `set` and `cue`. Plays nothing.
- **Shared state**: only `@state` (set/get), `@cues` (cue/sync), and `@t0`. Everything else is per-thread.

The system is mostly idle threads waking up at precisely the right wall-clock instants. The only real-time pressure is keeping `LOOKAHEAD` (~200ms) of bundles queued in scsynth — wider lookahead = more drift-tolerance, narrower = more responsive to live changes.
