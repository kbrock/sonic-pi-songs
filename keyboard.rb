# Keyboard-driven chord progression
#
# Keys 1-7: select chord degree
# 0+digit: change root key (03 = C)
# 91: print chord guide
#
# Root mapping: 0=C 1=C# 2=D 3=Eb 4=E 5=F 6=F# 7=G 8=Ab 9=A
#
# In a major key, degrees map to:
#   1=I(maj) 2=ii(min) 3=iii(min) 4=IV(maj) 5=V(maj) 6=vi(min) 7=vii(dim)
# e.g. key of G: 1=G 2=Am 3=Bm 4=C 5=D 6=Em 7=F#dim

use_bpm 90

root = :G3
sc = :major
degree = 1
prefix = nil

roots = [:C3, :Cs3, :D3, :Eb3, :E3, :F3, :Fs3, :G3, :Ab3, :A3]
root_names = %w[C C# D Eb E F F# G Ab A]

live_loop :key_listener do
  v = sync(:key)
  n = v[:n]

  if prefix == 0
    if n < roots.length
      root = roots[n]
      puts "Root: #{root_names[n]}"
    end
    prefix = nil
  elsif prefix == 9
    if n == 1
      idx = roots.index(root) || 7
      names = scale(root, sc).take(7).map { |n| note_info(n).midi_note_to_str.gsub(/\d/, '') }
      quals = %w[maj min min maj maj min dim]
      chords = names.zip(quals).each_with_index.map { |(nm, q), i| "#{i+1}=#{nm}#{q}" }
      puts "Key of #{root_names[idx]}: #{chords.join(' ')}"
    end
    prefix = nil
  elsif n == 0 || n == 9
    prefix = n
  elsif n.between?(1, 7)
    degree = n
    puts "Degree: #{degree}"
  end
end

live_loop :bass do
  note = scale(root, sc)[degree - 1]
  synth :fm, note: note, release: 0.4, amp: 0.6
  sleep 0.5
  synth :fm, note: note, release: 0.2, amp: 0.4
  sleep 0.5
end

live_loop :pad do
  sync :bass
  notes = chord_degree(degree, root, sc, 3)
  synth :prophet, notes: notes, release: 1.8, amp: 0.3, cutoff: 80
  sleep 2
end
