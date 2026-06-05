require "osc-ruby"

# Make Sonic Pi's bundled Ruby lib available before requiring sonicpi/*
$LOAD_PATH.unshift "/Applications/Sonic Pi.app/Contents/Resources/app/server/ruby/lib"

require "sonicpi/note"

require_relative "util"
require_relative "synth_info"

module SonicMyPi
  PIROOT    = "/Applications/Sonic Pi.app/Contents/Resources"
  SCSYNTH   = "#{PIROOT}/app/server/native/scsynth"
  SYNTHDEFS = "#{PIROOT}/etc/synthdefs/compiled"
  SAMPLES   = "#{PIROOT}/etc/samples"

  class Synth
    include Util

    G_MUSIC = 100  # all music synths attach here
    G_FX    = 101  # fx synths attach here; runs after G_MUSIC each audio frame

    # reference to osc client
    attr_accessor :client
    attr_reader :sampledir

    # thread local values
    attr_accessor :synth
    attr_accessor :bpm
    attr_accessor :offset

    def initialize(client:, sampledir: SAMPLES)
      @sampledir = sampledir
      @client    = client
      @bufs      = {}
      @next_buf  = 0

      # state
      @bpm    = 120
      @synth  = :hollow
      # 50ms latency + server start
      @t0     = Time.now + 0.05 + 0.5
      @offset = 0

      @live_loops   = []
      @loop_warned  = {}

      @fx_bus_stack   = []
      @fx_group_stack = []
      @free_buses     = []    # released bus numbers + the wall time they're safe to reuse
      @next_fx_bus    = 2     # busses 0,1 are stereo hardware out; private busses start at 2
      @next_fx_group  = 1000  # group IDs above G_MUSIC/G_FX reserved range
      @next_fx_node   = 2000  # fx node IDs distinct from group IDs
    end

    # use_synth
    # notes = (ring chord(:a3, :m7), chord(:f3, :major7), chord(:c3, :major7), chord(:g3, :major7))
    # play notes.tick, attack: 4, release: 6, amp: 0.5
    def use_bpm(value) = @bpm = value

    DISPATCH_LOOKAHEAD = 0.2  # seconds of audio pre-scheduled into scsynth
    AUTO_SLEEP_BEATS   = 0.25 # used when a live_loop body returns without sleeping

    def live_loop(name, *_opts, &block)
      @live_loops << { name: name, block: block, next_offset: @offset }
    end

    # Rolling-window dispatcher. Runs forever; exit via Ctrl-C.
    def dispatch_loops!
      return if @live_loops.empty?
      loop do
        soonest = @live_loops.min_by { |ll| ll[:next_offset] }
        horizon = (Time.now - @t0) + DISPATCH_LOOKAHEAD

        if soonest[:next_offset] <= horizon
          @offset = soonest[:next_offset]
          before  = @offset
          self.class.yield_to(self, &soonest[:block])
          if @offset == before
            unless @loop_warned[soonest[:name]]
              warn "live_loop :#{soonest[:name]} body did not sleep — auto-sleeping #{AUTO_SLEEP_BEATS} beats per iteration"
              @loop_warned[soonest[:name]] = true
            end
            sleep(AUTO_SLEEP_BEATS)
          end
          soonest[:next_offset] = @offset
        else
          Kernel.sleep(soonest[:next_offset] - horizon)
        end
      end
    end

    def use_synth(new_synth)
      @synth = SynthInfo.synth_alias(new_synth)
    end

    # Evaluate a song file in the synth's context. Inside the file, `use_bpm`,
    # `live_loop`, `play`, etc. resolve as instance methods — no `s.` prefix.
    def load_file(path)
      instance_eval(File.read(path), path)
    end

    # Route every synth created inside the block through a fresh fx synth on a
    # private audio bus. Per Sonic Pi's model: each call spawns a new group +
    # fx node (so opts are re-evaluated per call — `rand` works); music synths
    # in the block live in that group; at block exit we gate the fx and free
    # the group after its tail. Nests by stacking: inner block's group goes to
    # the head of G_FX so it executes before outer's, and the inner fx writes
    # to outer's in_bus.
    def with_fx(name, **opts)
      fx = SynthInfo.fx(name) or raise "unknown fx: #{name.inspect}"
      in_bus     = allocate_fx_bus
      group_id   = (@next_fx_group += 1)
      fx_node    = (@next_fx_node += 1)
      parent_out = @fx_bus_stack.last || 0

      send_msg("/g_new", group_id, 0, G_FX)
      ctrl = scale_opts(opts).flat_map { |k, v| [k.to_s, v.to_f] }
      send_msg("/s_new", "sonic-pi-#{fx[:synthdef]}", fx_node, 1, group_id,
               "in_bus", in_bus.to_f, "out_bus", parent_out.to_f, *ctrl)

      @fx_bus_stack.push(in_bus)
      @fx_group_stack.push(group_id)
      yield
    ensure
      @fx_bus_stack.pop
      group = @fx_group_stack.pop
      if group
        gate_at = @t0 + @offset
        free_at = gate_at + fx[:tail] + 0.2
        @client.send(OSC::Bundle.new(gate_at, OSC::Message.new("/n_set", fx_node, "gate", 0.0)))
        @client.send(OSC::Bundle.new(free_at, OSC::Message.new("/n_free", group)))
        @free_buses << { bus: in_bus, free_at: free_at }
      end
    end

    # Pull a bus whose previous fx has finished its tail; otherwise grow the
    # monotonic counter. The free-list avoids exhausting SC's ~1008 private
    # buses over a long session.
    def allocate_fx_bus
      now = Time.now
      if (idx = @free_buses.index { |e| e[:free_at] <= now })
        @free_buses.delete_at(idx)[:bus]
      else
        bus = @next_fx_bus
        @next_fx_bus += 2  # stereo: claim a pair even if only one is referenced as in_bus
        bus
      end
    end

    # def measure
    #   @t0     = Time.now + 0.1 # 100ms latency
    #   @offset = 0
    # end

    def sleep(beats)
      @offset += beats_to_seconds(beats)
    end

    def beats_to_seconds(beats)
      beats * 60.0 / @bpm
    end

    def scale_opts(opts)
      opts.to_h { |k, v| [k, SynthInfo.beat_scaled?(k) ? beats_to_seconds(v) : v] }
    end

    def s_new(synth_name, **opts)
      group = @fx_group_stack.last || G_MUSIC
      opts = { out_bus: @fx_bus_stack.last }.merge(opts) unless @fx_bus_stack.empty?
      ctrl = scale_opts(opts).flat_map { |k, v| [k.to_s, v.to_f] }
      OSC::Message.new("/s_new", "sonic-pi-#{synth_name}", -1, 0, group, *ctrl)
    end

    def play(notes, **opts)
      msgs = resolve_notes(notes).map { |n| s_new(synth, **opts, note: n) }
      send_bundle(msgs)
    end

    # sample :bd_tek, amp: 1.2, cutoff: 90
    def sample(name, **opts)
      send_bundle(s_new(:basic_stereo_player, buf: bbuf(name), **opts))
    end

    # load synth defs
    def upload(file)
      if Dir.exist?(file)
        send_msg("/d_loadDir", file)
      else
        bytes = File.binread(file)
        send_msg("/d_recv", OSC::OSCBlob.new(bytes))
      end

      self
    end

    # load samples (they get plreloaded / and auto unloaded?)
    def preload(*names)
      names.each { |name| bbuf(name) }
    end

    def sync(delay = 0.5)
      Kernel.sleep(delay)
      @t0 += delay
    end

    def resolve_notes(notes)
      if notes.kind_of?(Array)
        notes
      elsif notes.kind_of?(Symbol)
        [SonicPi::Note.resolve_midi_note(notes)]
      else
        [notes]
      end
    end

    def bbuf(name)
      @bufs[name] ||= begin
        bufnum = @next_buf
        @next_buf += 1
        filename = File.exist?(name.to_s) ? name.to_s : "#{sampledir}/#{name}.flac"
        send_msg("/b_allocRead", bufnum, filename)
        bufnum
      end
    end

    def send_bundle(messages)
      messages = [messages] unless messages.is_a?(Array)
      @client.send(OSC::Bundle.new(@t0 + @offset, *messages))
    end

    def send_msg(*args)
      @client.send(OSC::Message.new(*args))
      self
    end

    # def send(*args)
    #   @client.send(*args)
    #   self
    # end

    def self.run(synths: SYNTHDEFS, sampledir: SAMPLES, host: "127.0.0.1", port: 57110, &block)
      scsynth_pid = spawn_synth(port: port)
      synth = new(client: OSC::Client.new(host, port), sampledir: sampledir)
      add_cleanup_on_shutdown(synth, scsynth_pid)
      if synths
        synth.upload(synths)
      end
      synth.send_msg("/g_new", G_MUSIC, 0, 0)        # head of root
      synth.send_msg("/g_new", G_FX, 3, G_MUSIC)     # immediately after G_MUSIC
      synth.sync(0.3)
      yield_to(synth, &block) if block_given?
      synth.dispatch_loops!
      synth
    end

    def self.add_cleanup_on_shutdown(synth, scsynth_pid)
      at_exit do
        synth.send_msg("/clearSched") rescue nil
        synth.send_msg("/g_freeAll", 0) rescue nil
        synth.sync(0.05)
        synth.send_msg("/quit") rescue nil
        Process.wait(scsynth_pid) rescue nil
      end
      trap("INT")  { exit }
      trap("TERM") { exit }
    end

    def self.yield_to(synth, &block)
      block.arity == 0 ? synth.instance_eval(&block) : block.call(synth)
    end

    def self.spawn_synth(port: 57110, device: default_output_device)
      puts "scsynth output device: #{device || "(scsynth default)"}"

      args = [SCSYNTH, "-u", port.to_s, "-i", "0"]
      args += ["-H", "", device] if device
      pid = spawn(*args)
      Kernel.sleep(0.5) # NOTE: this number is hardcoded into Synth.t0
      pid
    end

    def self.default_output_device
      out = `system_profiler SPAudioDataType 2>/dev/null`
      current = nil
      out.each_line do |line|
        if line =~ /^        (\S.*?):\s*$/
          current = $1
        elsif line.include?("Default Output Device: Yes") && current
          return current
        end
      end
      nil
    end
  end
end
