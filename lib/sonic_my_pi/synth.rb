require "osc-ruby"

require "sonicpi/note"

require_relative "util"

module SonicMyPi
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

    def initialize(host, port, sampledir: nil)
      @sampledir = sampledir
      @client   = OSC::Client.new(host, port)
      @bufs     = {}
      @next_buf = 0

      # state
      @bpm    = 120
      @synth  = :hollow
      # 50ms latency + server start
      @t0     = Time.now + 0.05 + 0.5
      @offset = 0
    end

    # use_synth
    # notes = (ring chord(:a3, :m7), chord(:f3, :major7), chord(:c3, :major7), chord(:g3, :major7))
    # play notes.tick, attack: 4, release: 6, amp: 0.5
    def use_bpm(value) = @bpm = value

    def use_synth(new_synth)
      @synth = SYNTH_ALIASES.fetch(new_synth, new_synth)
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
        [SonicPi::Note.resolve_note_name(notes)]
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

    def self.run(synths: nil, port: 57110, sampledir: nil, &block)
      puts "spawn scsynth process"
      scsynth_pid = spawn_synth(port: port)
      puts "/spawn"
      synth = new("127.0.0.1", port, sampledir: sampledir)
      if synths
        puts "upload synthesizers"
        synth.upload(synths)
        synth.sync(0.3)
        puts "/upload"
      end

      at_exit do
        synth.send_msg("/g_freeAll", 0) rescue nil
        synth.sync(0.05)
        synth.send_msg("/quit") rescue nil
        Process.wait(scsynth_pid) rescue nil
      end

      trap("INT")  { exit }
      trap("TERM") { exit }

      block.arity == 0 ? synth.instance_eval(&block) : block.call(synth) if block_given?
      synth
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
