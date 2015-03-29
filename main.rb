# Sample sentence retriever: Given a Japanese word, or tab-delim
# filename (word in first column), retrieves sentences from wwwjdic.
#
# Call format:
# ruby main.rb <filename or word> <number of sentences to show, default is 5>
#
# Sample runs (both retrieve 2 sentences):
#   ruby main.rb somefile.txt 2
#   ruby main.rb <japanese_word> 2


# Calls WWWJDIC backdoor, gets example sentences for word.
# Returns array of arrays:
# [ [ "jp example 1", "eng translation" ], [ "jp ex 2", "eng" ] ... ]
def get_sentences(word)
  url="http://www.csse.monash.edu.au/~jwb/cgi-bin/wwwjdic.cgi?1ZEU#{word}=1"
  ret = `curl -s #{url}`
  data = ret.gsub(/.*\<pre\>/m, '').gsub(/\<\/pre\>.*/m, '')
  sentences = data.split("\n").select { |s| s =~ /^A/ }
  sentences.map! do |s|
    s.gsub( /^A:/, '').
      gsub(/#ID=.*$/, '').
      strip.
      split("\t")
  end
  sentences
end


input = ARGV[0]
num_sentences = (ARGV[1] || "5").to_i

# if the input is a file, get the words from the first column of the
# file (tab-separated)
if (File.exist?(input))
  data = File.read(input)
  lines = data.split("\n")
else
  lines = [ input ]
end


# For each line, print the line as-is, and then a selection of
# sentence below it.  This way, I can (reasonably) quickly manually
# edit the file, and put the sentence that I want at the end of the
# file line.
lines.each do |line|
  word = line.gsub( /\t.*/, '').strip
  puts line
  sentences = get_sentences(word)[0..(num_sentences-1)]
  sentences = [[ "?", "?" ]] if (sentences.size == 0)
  sentences.each do |j, e|
    puts "\t#{j}\t#{e}"
  end
end


