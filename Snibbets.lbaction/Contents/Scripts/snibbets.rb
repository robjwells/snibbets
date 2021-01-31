#!/usr/bin/env ruby
# Snibbets 1.0.0

require 'optparse'
require 'readline'
require 'json'
require 'cgi'
require 'logger'

$search_path = File.expand_path(
  ENV['SNIBBETS_PATH'] || "~/Dropbox/notes/snippets"
)

class String
  # Are there multiple snippets (indicated by ATX headers)
  def multiple?
    scan(/^#+/).length > 1
  end

  # Is the snippet in this block fenced?
  def fenced?
    count = scan(/^```/).length
    count > 1 && count.even?
  end

  def rx
    ".*" + gsub(/\s+/,'.*') + ".*"
  end

  # remove outside comments, fences, and indentation
  def clean_code
    # if it's a fenced code block, just discard the fence and everything
    # outside it
    if fenced?
      return block.gsub(/(?:^|.*?\n)(`{3,})(\w+)?(.*?)\n\1.*/m) {|m| $3.strip }
    end

    # assume it's indented code, discard non-indented lines and outdent
    # the rest
    indent = nil
    inblock = false
    code = []
    split(/\n/).each {|line|
      if line.strip.empty? && inblock
        code.push(line)
      elsif line =~ /^( {4,}|\t+)/
        inblock = true
        indent ||= $1
        code.push(line.delete_prefix(indent))
      else
        inblock = false
      end
    }
    code.join("\n")
  end

  # Returns an array of snippets, with a title from the preceding header line.
  def snippets
    # Split content by ATX headers. Everything on the line after the #
    # becomes the title, code is gleaned from text between that and the
    # next ATX header (or end)
    parts = self.split(/^#+/)[1..]

    parts.map do |part|
      first, *rest = part.split("\n")
      title = first.strip.sub(/[.:]$/, '')
      code = rest.join("\n").clean_code.strip
      code.empty? ? {} : { 'title' => title, 'code' => code }
    end.reject(&:empty?)  # Filter out sections without code.
  end
end

def quit
  system('stty', `stty -g`.chomp)
  exit
end

# Generate a numbered menu, items passed must have a title property
def menu(res,title="Select one")
  lines = res.zip(1..).map do |match, count|
    "%2d) #{match['title']}" % count
  end
  $stderr.puts "\n" + lines.join("\n") + "\n\n"

  begin
    $stderr.printf(title.sub(/:?$/,": "),res.length)
    line = $stdin.readline(:chomp => true)
    quit unless line =~ /^[0-9]/
    line = line.to_i
    unless (1..res.length).include? line
      $stderr.puts "Out of range"
      return menu(res,title)
    end
    return res[line - 1]
  rescue Interrupt, EOFError => e
    quit
  end
end

# Search the snippets directory for query using Spotlight (mdfind)
def search_spotlight(query, folder, first_try = true)
  # First try only search by filenames
  nameonly = first_try ? '-name ' : ''
  matches = %x{mdfind -onlyin "#{folder}" #{nameonly}'#{query}'}.strip

  results = matches.split(/\n/).map do |line|
    { 'title' => File.basename(line, '.*'), 'path' => line }
  end

  if results.empty? && first_try
      # if no results on the first try, try again searching all text
      return search_spotlight(query, folder, false)
  end

  results
end

# Search the snippets directory for query using find and grep
def search(query, folder, first_try = true)
  # First try only search by filenames

  cmd = if first_try
          %Q{find "#{folder}" -iregex '^#{Regexp.escape(folder)}/#{query.rx}'}
        else
          %Q{grep -iEl '#{query.rx}' "#{folder}/"*}
        end

  matches = %x{#{cmd}}.strip

  results = matches.split(/\n/).map do |line|
    { 'title' => File.basename(line, '.*'), 'path' => line }
  end

  # if no results on the first try, try again searching all text
  results.empty? && first_try ? search(query, folder, false) : results
end

def parse_options
  options = {}

  optparse = OptionParser.new do|opts|
    opts.banner = "Usage: #{File.basename(__FILE__)} [options] query"

    opts.on("-h","--help",'Display this screen') do
      puts optparse
      Process.exit 0
    end

    # Set defaults.
    options[:interactive] = true
    options[:launchbar] = false
    options[:output] = "raw"
    options[:source] = File.expand_path($search_path)

    opts.on( '-q', '--quiet', 'Skip menus and display first match') do
      options[:interactive] = false
    end

    valid_formats = %w(json launchbar lb raw)
    opts.on( '-o', '--output FORMAT', "Output format (#{valid_formats.join(', ')})" ) do |outformat|
      outformat = outformat.strip.downcase
      if outformat =~ /^(lb|launchbar)$/
        options[:launchbar] = true
        options[:interactive] = false
      else
        options[:output] = outformat if valid_formats.include?(outformat)
      end
    end

    opts.on('-s', '--source FOLDER', 'Snippets folder to search') do |folder|
      options[:source] = File.expand_path(folder)
    end

  end

  optparse.parse!
  [options, optparse.help]
end

def construct_query(options)
  if options[:launchbar] && STDIN.stat.size > 0
    STDIN.read.force_encoding('utf-8')
  else
    ARGV.join(" ")  # If ARGV is empty, so is the query.
  end
end

def validate_query!(query, optparse)
  if query.strip.empty?
    puts "No search query"
    puts optparse
    Process.exit 1
  end
end

def build_launchbar_output(results)
  results.map do |result|
    title = result["title"]
    path = result["path"]
    snippets = IO.read(path).snippets
    next if snippets.empty?

    children = snippets.map do |snippet|
      {
        'title' => snippet['title'],
        'quickLookURL' => %Q{file://#{path}},
        'action' => 'pasteIt',
        'actionArgument' => snippet['code'],
        'label' => 'Paste'
      }
    end

    {
      'title' => title,
      'quickLookURL' => %Q{file://#{path}},
      'children' => children
    }
  end
end

options, help_message = parse_options()
query = CGI.unescape(construct_query(options))
validate_query!(query, help_message)
results = search(query, options[:source])

# No results.
if results.empty?
  if options[:launchbar]
    out = { 'title' => "No matching snippets found" }.to_json
    $stdout.puts out
  else
    $stderr.puts "No results"
  end
  Process.exit 0
end

# At least some results.
if options[:launchbar]
  puts build_launchbar_output(results).to_json
elsif !options[:interactive]
  snippets = IO.read(results[0]["path"]).snippets
  code_only = snippets.map { |s| s["code"] }
  output = options[:output] == 'json' ? snippets.to_json : code_only
  $stdout.puts output
else
  chosen_file = menu(results, "Select a file")
  snippets = IO.read(chosen_file["path"]).snippets

  if snippets.empty?
    $stderr.puts "No snippets found"
    Process.exit 0
  end

  chosen_snippet = menu(snippets, "Select snippet")
  $stdout.puts chosen_snippet['code']
end
