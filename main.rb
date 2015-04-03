# Sample sentence retriever and Anki file builder.
#
# This script takes an input file as an argument, and several other
# arguments (see the help).  The input file is assumed to be
# tab-delimited, and the word to be looked up is assumed to be in
# first column, unless the file is generated from an imiwa export, in
# which case the first two (junk) column are ignored).
#
# The class WWWJDICExampleProvider gets example sentences via web call
# to wwwjdic.  The URL and result format is hard-coded, and will break
# if things change.
#
# Call format:
#
#   ruby main.rb <filename or word> [options]
#
# run "ruby main.rb --help" to see the options.
#
# The "test" subfolder contains some sample files, including a test
# dictionary.  Sample calls using those:
#
#   ruby main.rb test/test_testdictionary.txt --testdata test/testdictionary.yml -c -n 2
#   ruby main.rb test/test_rikaikun.txt -n 2 -r
#

require 'optparse'
require 'yaml'


############################
# "Sentence Example" providers
#

class ExampleProvider
  # Returns array of arrays:
  # [ [ "jp example 1", "eng translation" ], [ "jp ex 2", "eng" ] ... ]
  # Should return empty array if no match.
  def get_sentences(word)
    raise "Subclasses must override."
  end
end

# Calls WWWJDIC backdoor, gets example sentences for word.
# Does raw html parsing.
class WWWJDICExampleProvider < ExampleProvider
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
end


# Gets sentences from a file.  Useful during development
class TestFileExampleProvider < ExampleProvider
  def initialize(filepath)
    @data = YAML.load(File.read(filepath))
  end

  def get_sentences(word)
    @data[word] || []
  end
end

############################

# Return a hash describing the options.
def parse_args(args)
  options = {
    :excount => 5,
    :testdata => nil,
    :console => false,
    :raw => false,
    :pronounciation_offset => 1,
    :definition_offset => 2
  }

  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} <input filepath> [options]"

    opts.separator ""
    opts.separator "Data options:"
    opts.on("-p N", Integer, "Offset to pronunciation column, default 1") do |n|
      options[:pronounciation_offset] = n
    end
    opts.on("-d N", Integer, "Offset to definition column, default 2") do |n|
      options[:definition_offset] = n
    end
    opts.on("-n N", Integer, "Number of example sentences, default 5") do |n|
      options[:excount] = n
    end

    opts.separator ""
    opts.separator "Testing:"
    opts.on("-t", "--testdata [DATAFILE]",
            "Path to yaml data file of examples (useful for testing)") do |d|
      options[:testdata] = d
    end

    opts.separator ""
    opts.separator "Output:"
    opts.on("-c", "--console", "Dump to console only") do |c|
      options[:console] = c
    end
    opts.on("-r", "--raw", "Output raw data (all examples)") do |c|
      options[:raw] = c
    end

    opts.separator ""
    opts.on_tail("-h", "--help", "Show this message") do
      puts opts
      exit
    end
  end

  opt_parser.parse!(args)
  options
end


# imiwa exports multiple variants, comma-separated.  User may need to
# intervene using command-line, but only if multiple words return
# examples.  Returns the new record, with populated sentences.
def get_lookup_selection(record, provider)

  w = record[:word].strip
  puts "Resolving \"#{w}\" ..."

  candidates = w.split(",").map{ |t| t.strip }

  # Print the candidates and the number of sentences returned on
  # lookup.  User chooses the candidate, sentences are stored.  Note
  # that if only one of the words has sample sentences, no
  # intervention is required.
  sentences = {}
  autoselection = nil
  candidates.each_with_index do |c, index|
    print "#{index + 1}. #{c} ... "
    s = provider.get_sentences(c)
    autoselection = index + 1 if (s.size > 0)
    puts "#{s.size} sentences"
    sentences[c] = s
  end

  can_autoselect = (sentences.values.count { |s| s.size > 0 } == 1)
  selected = can_autoselect ? autoselection :
    get_selection_number("Enter selection: ", 1, candidates.size)

  selection = candidates[selected - 1]
  puts "Selected: #{selection}"
  record[:word] = selection
  record[:sentences] = sentences[selection]

  record
end

def get_selection_number(prompt, min, max)
  print prompt
  n = $stdin.gets.chomp.strip.to_i  # $stdin required, wasn't waiting for input
  n = min if n < min
  n = max if n > max
  n
end

# For each line in the file, return array of "useful" parts
# { :word => "", :pronounciation => "", :parts => [], :sentences => [] }
def get_data_array(filepath, word_index, pronounciation_offset)
  lines = File.read(filepath).split("\n")

  data = lines.select { |lin| (lin || "").strip != "" }.map do |lin|
    parts = lin.split("\t").map { |s| s.strip }

    # imiwa files have two junk fields at the beginning
    if (["jmdict", "kanjidic"].include?(parts[0].downcase))
      parts = parts[2..-1]
      if (parts[parts.size - 1] == "Favorites")
        parts = parts[0..(parts.size - 2)]
      end
    end

    { :word => parts[0], :pronounciation => parts[pronounciation_offset], :parts => parts }
  end

  # Ensure all data lines have the same number of parts - Anki balks
  # when there are different field counts.
  parts_count = data[0][:parts].size
  exceptions = data.select { |d| d[:parts].size != parts_count }
  if (exceptions.size > 0)
    puts "Bad list, expected field count = (#{parts_count}), exceptions below:"
    exceptions.each do |e|
      puts "  #{e[:parts].size} fields: #{e[:parts].join("\t")}"
    end
    exit 1
  end

  return data
end

def get_sentences(data, provider, num_sentences)

  data.map! { |d| d[:sentences] = []; d }

  # Imiwa exports words with multiple variants, which breaks WWWJDIC
  # lookup.  Get user input on which should be the actual word used for
  # lookup.
  if (data.select { |d| d[:word] =~ /,/ }.size > 0)
    puts "Some words in the input list need to be further specified (comma-separated)."
    puts "For each question below, specify the number that should be used for lookup."
    data.select { |d| d[:word] =~ /,/ }.map! do |d|
      get_lookup_selection(d, provider)
    end
  end

  # Do lookup, get sentences.
  data.select { |d| d[:sentences].size == 0 }.map! do |d|
    print "Looking up \"#{d[:word]}\" ... "
    s = provider.get_sentences(d[:word])
    puts "#{s.size} sentences"
    d[:sentences] = s
    d
  end

  # Sort shorter english sentences to the top, assuming they're more
  # succinct examples.
  data.map! do |d|
    s = d[:sentences].sort { |a, b| a[1].size <=> b[1].size }
    d[:sentences] = s[0..(num_sentences-1)]
    d
  end

  data
end

# For each data record, if it has more than one sentence, output the sentences
# and ask user to pick the best one.
def preserve_best_sentences(data)
  puts "For each word with multiple examples below, choose the best selection:"

  total_words = data.count { |d| d[:sentences].size > 1 }
  curr_word = 0
  data.select { |d| d[:sentences].size > 1 }.map! do |d|
    curr_word += 1
    puts "#{curr_word} of #{total_words}: #{d[:word]} (#{d[:pronounciation]})"
    d[:sentences].each_with_index do |s, i|
      puts "#{i + 1}.\t#{s[0]}"
      puts "\t#{s[1]}"
    end
    n = get_selection_number("Best sentence: ", 1, d[:sentences].size)
    selection = d[:sentences][n - 1]
    d[:sentences] = [ [ selection[0], selection[1] ] ]
    d
  end

  puts "\nDone."
end


# Print out the data
def output_report(data, ostream)
  # Sort entries with many entries to the top: they'll be hardest to
  # deal with, so get them out of the way first.
  data.sort! { |a, b| -1 * a[:sentences].size <=> -1 * b[:sentences].size }

  # For each line with multiple sentences, print the line as-is, and
  # then a selection of sentences below it.  This way, I can
  # (reasonably) quickly manually edit the file, and put the sentence
  # that I want at the end of the file line.
  data.select { |d| d[:sentences].size > 1 }.each do |d|
    ostream.puts d[:parts].join("\t")
    d[:sentences].each { |j, e| ostream.puts "\t#{j}\t#{e}" }
    ostream.puts
  end

  # Add items that have a single example.
  data.select { |d| d[:sentences].size == 1 }.each do |d|
    output = d[:parts].clone
    jp, eng = d[:sentences][0]
    output << jp
    output << eng
    ostream.puts output.join("\t")
  end

  # Add the remaining items with dummy examples.
  data.select { |d| d[:sentences].size == 0 }.each do |d|
    output = d[:parts].clone
    output << "?"
    output << "?"
    ostream.puts output.join("\t")
  end
end

def output_files(data, input_filename, options)
  # Output.
  file_dir = File.expand_path(File.dirname(input_filename))
  file_basename = File.basename(input_filename, File.extname(input_filename))
  basepath = File.join(file_dir, file_basename)
  file_suffix = DateTime.now().strftime("%Y%m%d_%H%M%S")

  # If any words have more than one example, the user has to select the
  # best example available.
  have_multiple_examples =  data.any? { |d| d[:sentences].size > 1 }

  # Only print the raw data if it will differ from the final summary
  # (that is, if some words have multiple examples).
  if (options[:raw] && have_multiple_examples)
    if (options[:console])
      puts "\nRaw results:"
      output_report(data, $stdout)
    else
      filepath = "#{basepath}_raw_#{file_suffix}.txt"
      puts "Outputting raw data to #{filepath}"
      File.open(filepath, "w") { |f| output_report(data, f) }
    end
  end

  if (have_multiple_examples)
    puts "\nUser intervention required to select best sentences."
    print "Continue? (y/n, default is y): "
    s = $stdin.gets.chomp.strip.downcase
    if (s != "y" && s != "")
      puts "Quitting."
      exit 0
    end
    puts
    preserve_best_sentences(data)
  end

  if (options[:console])
    puts "\nProcessed data:"
    output_report(data, $stdout)
  else
    filepath = "#{basepath}_output_#{file_suffix}.txt"
    puts "Generating #{filepath}"
    File.open(filepath, "w") { |f| output_report(data, f) }
  end

end

############################
# Main
#

options = parse_args(ARGV)

if (ARGV.size != 1)
  puts "Missing input file path."
  exit 1
end

input = ARGV[0]
if (!File.exist?(input))
  puts "Invalid/missing file name"
  exit 1
end

provider =
  options[:testdata].nil? ? WWWJDICExampleProvider.new() : 
  TestFileExampleProvider.new(options[:testdata])
num_sentences = options[:excount]
po = options[:pronounciation_offset]

rawdata = get_data_array(input, 0, po)
data = get_sentences(rawdata, provider, num_sentences)

output_files(data, input, options)
