require "osc-ruby"

require "sonicpi/chord"
require "sonicpi/note"
require "sonicpi/scale"

module SonicMyPi
  class Synth
    attr_accessor :client
    attr_accessor :synth # following pi, not thrilled
    attr_reader :sampledir
    attr_accessor :bpm

    def initialize(host, port, sampledir: nil)
      @sampledir = sampledir
      @client   = OSC::Client.new(host, port)
      @bufs     = {}
      @next_buf = 0

      # state
      @bpm    = 120
      @synth  = :hollow
      # sleep 0.5, 0.3, 100ms latency
      @t0     = Time.now + 0.85 # 100ms latency
      @offset = 0
    end

    # use_synth
    # notes = (ring chord(:a3, :m7), chord(:f3, :major7), chord(:c3, :major7), chord(:g3, :major7))
    # play notes.tick, attack: 4, release: 6, amp: 0.5
    def use_bpm(value) = @bpm= value

    def use_synth(new_synth)
      @synth = new_synth
    end

    # def measure
    #   @t0     = Time.now + 0.1 # 100ms latency
    #   @offset = 0
    # end

    def sleep(delay)
      @offset += delay
    end

    def chord(root, name)
      SonicPi::Chord.new(root, name)
    end

    def play(notes, **opts)
      # synth = opts.delete(:synth) || @synth
      base = ["/s_new", "sonic-pi-#{synth}", -1, 0, 0]
      # controls =
      control = opts.flat_map { |n, v| [n.to_s, v.to_f] }

      notes = resolve_notes(notes)
      messages = notes.map { |note| [*base, *control, "note", note.to_f] }
      send_play(messages)
    end

    # TODO: do I want to set default values for the args? kwargs if so
    # TODO: ensure correct type for values
    # sample :bd_tek, amp: 1.2, cutoff: 90
    def sample(name, **opts)
      # amp: 1.0, rate: 1.0
      base = ["/s_new", "sonic-pi-basic_stereo_player", -1, 0, 0]
      # controls
      control = opts.flat_map { |n, v| [n.to_s, v.to_f] }
      send_play([*base, "buf", bbuf(name), *control])
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
    end

    def resolve_notes(notes)
      if notes.kind_of?(Array)
        notes
      elsif notes.kind_of?(Symbol)
        [Note.resolve_note_name(notes)]
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

    def send_play(messages)
      message =
        if messages&.first.kind_of?(Array)
          messages.map { |msg| OSC::Message.new(*msg)}
        else
          [OSC::Message.new(*messages)]
        end
      # WORKS:
      # message.each { |msg| @client.send(msg) }
      # BROKEN:
      @client.send(OSC::Bundle.new(@t0 + @offset, *message))
    end

    def send_msg(*args)
      @client.send(OSC::Message.new(*args))
      self
    end

    # def send(*args)
    #   @client.send(*args)
    #   self
    # end

    def self.run(synths: nil, port: 57110, sampledir: nil)
      puts "spawn"
      scsynth_pid = spawn_synth(port: port)
      Kernel.sleep(0.5)
      puts "/spawn"
      synth = new("127.0.0.1", port, sampledir: sampledir)
      if synths
        synth.upload(synths)
        puts "upload"
        synth.sync(0.3)
        puts "/upload"
      end

      if block_given?
        begin
          trap("TERM") { raise Interrupt }   # so ensure runs on kill
          yield synth
        ensure
          synth&.msg("/quit") rescue nil
          Process.wait(scsynth_pid) rescue nil if scsynth_pid
        end
      else
        at_exit do
          synth.msg("/g_freeAll", 0)   # free every running node in default group
          puts "freeing"
          synth.sync(0.05)
          synth.msg("/quit") rescue nil
          Process.wait(scsynth_pid) rescue nil
        end

        trap("INT")  { exit }
        trap("TERM") { exit }

        synth
      end
    end

    def self.spawn_synth(port: 57110, device: default_output_device)
      puts "scsynth output device: #{device || "(scsynth default)"}"

      args = [SCSYNTH, "-u", port.to_s, "-i", "0"]
      args += ["-H", "", device] if device
      # returns pid
      spawn(*args)
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
