require "osc-ruby"

# Make Sonic Pi's bundled Ruby lib available before requiring sonicpi/*
$LOAD_PATH.unshift "/Applications/Sonic Pi.app/Contents/Resources/app/server/ruby/lib"

require "sonicpi/note"

require_relative "util"

module SonicMyPi
  PIROOT    = "/Applications/Sonic Pi.app/Contents/Resources"
  SCSYNTH   = "#{PIROOT}/app/server/native/scsynth"
  SYNTHDEFS = "#{PIROOT}/etc/synthdefs/compiled"
  SAMPLES   = "#{PIROOT}/etc/samples"

  class Synth
    include Util

    SYNTH_ALIASES = {
      sine:     :beep,
      mod_beep: :mod_sine,
    }.freeze

    BEAT_SCALED_OPTS = %i[attack decay sustain release].freeze

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
    end

    # use_synth
    # notes = (ring chord(:a3, :m7), chord(:f3, :major7), chord(:c3, :major7), chord(:g3, :major7))
    # play notes.tick, attack: 4, release: 6, amp: 0.5
    def use_bpm(value) = @bpm = value

    DISPATCH_LOOKAHEAD = 2.0  # seconds of audio pre-scheduled into scsynth
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
      @synth = SYNTH_ALIASES.fetch(new_synth, new_synth)
    end

    # Evaluate a song file in the synth's context. Inside the file, `use_bpm`,
    # `live_loop`, `play`, etc. resolve as instance methods — no `s.` prefix.
    def load_file(path)
      instance_eval(File.read(path), path)
    end

    # no-op for v1: yields the block unchanged. v2 will route through an fx synth on a private bus.
    def with_fx(_name, **_opts)
      yield
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
      opts.to_h { |k, v| [k, BEAT_SCALED_OPTS.include?(k) ? beats_to_seconds(v) : v] }
    end

    def s_new(synth_name, **opts)
      ctrl = scale_opts(opts).flat_map { |k, v| [k.to_s, v.to_f] }
      OSC::Message.new("/s_new", "sonic-pi-#{synth_name}", -1, 0, 0, *ctrl)
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
        synth.sync(0.3)
      end
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
