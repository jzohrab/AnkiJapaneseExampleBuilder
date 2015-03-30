# Anki Japanese Example Builder

This is a simple command-line clone of EPWing2Anki (http://sourceforge.net/projects/epwing2anki/).  This program takes a text file kanji words and gets example sentences for each from wwwjic (specifically, http://www.csse.monash.edu.au/~jwb/cgi-bin/wwwjdic.cgi as documented at http://www.edrdg.org/wwwjdic/wwwjdicinf.html#backdoor_tag), and creates a new output file with samples included.

A sample run:

Given a tab-delimited file with Kanji in the first field, pronunciation the second field, and a definition in the third field, the following will generated a file with a sample Japanese sentence and its English equivalent in the fourth and fifth fields.

```
$ ruby main.rb test/test_rikaikun.txt -n 1
... [snip, some status reporting] ...
Generating /wwwjdic_examples/test/test_rikaikun_output_20150329_223014.txt
```

Notes:

* the output file is generated in the same folder as its input file
* if a sentence isn't found, "?" is placed in these fields so that Anki import doesn't complain about irregular field counts

# Usage

## Installation and Set Up

Other than setting up Ruby, and perhaps making main.rb executable, there shouldn't be anything to set up.  Just put main.rb in a folder and run it from the command line.

This has been written and tested on a Mac (`ruby 2.0.0p481 (2014-05-08 revision 45883) [universal.x86_64-darwin13]`).  It does not use any additional Ruby Gems.


## Usage

As shown in the header of `main.rb`, the program takes the input file as an argument, and a list of options.  The options can be seen by running `ruby main.rb --help`.

There are some sample files provided in the "test" subdirectory.

Note that program makes a web call to the online dictionary API for every word.  There is currently no support for local dictionaries.
