require_relative "test_helper"

describe SonicMyPi::Synth do
  describe "#use_synth" do
    it "stores the synth name" do
      synth = create_synth
      synth.use_synth :hollow
      assert_equal :hollow, synth.synth
    end

    it "resolves :sine to :beep" do
      synth = create_synth
      synth.use_synth :sine
      assert_equal :beep, synth.synth
    end
  end

  describe "#beats_to_seconds" do
    it "converts beats to seconds at 120 BPM" do
      synth = create_synth
      synth.use_bpm 120
      assert_equal 0.5, synth.beats_to_seconds(1)
      assert_equal 2.0, synth.beats_to_seconds(4)
    end

    it "converts beats to seconds at 60 BPM" do
      synth = create_synth
      synth.use_bpm 60
      assert_equal 1.0, synth.beats_to_seconds(1)
    end
  end

  describe "#sleep" do
    it "advances offset by beats-to-seconds" do
      synth = create_synth
      synth.use_bpm 120
      before = synth.offset
      synth.sleep 4
      assert_equal 2.0, synth.offset - before
    end
  end

  describe "#scale_opts" do
    it "scales beat-typed opts to seconds" do
      synth = create_synth
      synth.use_bpm 120
      result = synth.scale_opts(attack: 1, amp: 0.5)
      assert_equal 0.5, result[:attack]   # 1 beat = 0.5s
      assert_equal 0.5, result[:amp]      # passthrough
    end
  end

  describe "#play" do
    it "sends one OSC::Bundle per call" do
      synth = create_synth
      synth.use_synth :hollow
      synth.play 60
      assert_equal 1, synth.client.sent.size
      assert_kind_of OSC::Bundle, synth.client.sent.first
    end

    it "sends one /s_new message per note in a chord" do
      synth = create_synth
      synth.use_synth :hollow
      synth.play [60, 64, 67]
      bundle = synth.client.sent.first
      assert_equal 3, bundle.instance_variable_get(:@args).size
    end
  end

  describe "#sample" do
    it "sends a /b_allocRead before the bundle on first use" do
      synth = create_synth
      synth.sample :loop_amen
      assert_kind_of OSC::Message, synth.client.sent.first
      assert_kind_of OSC::Bundle,  synth.client.sent.last
    end

    it "caches buffer numbers across calls" do
      synth = create_synth
      synth.sample :loop_amen
      synth.sample :loop_amen
      alloc_reads = synth.client.sent.select { |m| m.is_a?(OSC::Message) && m.address == "/b_allocRead" }
      assert_equal 1, alloc_reads.size
    end
  end

  def create_synth
    SonicMyPi::Synth.new(client: FakeClient.new)
  end
end
