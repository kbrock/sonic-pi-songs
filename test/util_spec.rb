require_relative "test_helper"

describe SonicMyPi::Util do
  describe "#chord" do
    it "returns a SonicPi::Chord" do
      assert_kind_of SonicPi::Chord, helper.chord(:c4, :major)
    end
  end

  describe "#scale" do
    it "returns a SonicPi::Scale" do
      assert_kind_of SonicPi::Scale, helper.scale(:c4, :minor_pentatonic)
    end
  end

  describe "#rrand" do
    it "returns a float within [lo, hi)" do
      h = helper
      v = h.rrand(0, 10)
      assert_operator v, :>=, 0
      assert_operator v, :<,  10
    end

    it "is deterministic for a fixed seed" do
      assert_equal helper.rrand(0, 1), helper.rrand(0, 1)
    end
  end

  describe "#rrand_i" do
    it "returns an integer in [lo, hi]" do
      h = helper
      v = h.rrand_i(1, 6)
      assert_kind_of Integer, v
      assert_operator v, :>=, 1
      assert_operator v, :<=, 6
    end
  end

  describe "#choose" do
    it "returns one of the array elements" do
      assert_includes [:a, :b, :c], helper.choose([:a, :b, :c])
    end
  end

  describe "#one_in" do
    it "is sometimes true and sometimes false at n=2" do
      h = helper
      results = 50.times.map { h.one_in(2) }
      assert_includes results, true
      assert_includes results, false
    end
  end

  def helper
    Class.new { include SonicMyPi::Util }.new.tap { |o| o.instance_variable_set(:@seed, 42) }
  end
end
