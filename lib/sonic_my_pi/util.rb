require "sonicpi/chord"
require "sonicpi/note"
require "sonicpi/scale"

module SonicMyPi
  module Util
    def chord(root, name) = SonicPi::Chord.new(root, name)
    def scale(root, name, num_octaves: 1) = SonicPi::Scale.new(root, name, num_octaves)

    def rrand(lo, hi)     = lo + rng.rand * (hi - lo)
    def rrand_i(lo, hi)   = rng.rand(lo..hi)
    def choose(arr)       = arr[rng.rand(arr.size)]
    def one_in(n)         = rng.rand(n).zero?

    def rng
      @rng ||= Random.new(@seed || Random.new_seed)
    end
  end
end
