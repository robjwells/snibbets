#!/usr/bin/env ruby
# Snibbets 1.0.0

require 'optparse'
require 'readline'
require 'json'
require 'cgi'
require 'logger'

$search_path = File.expand_path(
  ENV['SNIBBETS_PATH'] || '~/Dropbox/notes/snippets'
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
    format('.*%s.*', gsub(/\s+/, '.*'))
  end

  def strip_fences
    gsub(/
      (?:^|.*?\n)       # Match either the line start or non-fence text,
      (?<fence> `{3,})  # then the opening fence
      (?: \w*)          # followed maybe by some word (eg language mode),
      (?<code> .*?)\n   # followed by some code,
      \k<fence>         # then the closing fence,
      .*                # and ignore anything else.
      /xm
    ) { |_match| Regexp.last_match(:code).strip }
  end

  # remove outside comments, fences, and indentation
  def clean_code
    # if it's a fenced code block, just discard the fence and everything
    # outside it
    return strip_fences if fenced?

    # assume it's indented code, discard non-indented lines and outdent
    # the rest
    indent = nil
    inblock = false
    code = []
    split("\n").each {|line|
      if inblock && line.strip.empty?
        code.push(line)
      elsif line =~ /^( {4,}|\t+)/
        inblock = true
        indent ||= Regexp.last_match(1)
        code.push(line.delete_prefix(indent))
      else
        inblock = false
      end
    }
    code.join("\n")
  end

  # Returns an optional Hash with the section's title (from an ATX header) and code.
  def parse_sections(part)
    first, *rest = part.split("\n")
    title = first.strip.sub(/[.:]$/, '')
    code = rest.join("\n").clean_code.strip
    { title: title, code: code } unless code.empty?  # nil for empty code.
  end

  # Returns an array of snippets, with a title from the preceding header line.
  def snippets
    # Split content by ATX headers. Everything on the line after the #
    # becomes the title, code is gleaned from text between that and the
    # next ATX header (or end)
    split(/^#+/)[1..]
      .map(&method(:parse_sections))
      .reject(&:nil?)  # Filters out nil for empty code.
  end
end

def quit
  system('stty', `stty -g`.chomp)
  exit
end

# Generate a numbered menu, items passed must have a title property
def menu(res, title = 'Select one')
  lines = res.zip(1..).map do |match, count|
    format('%2d) %s', count, match.fetch(:title))
  end
  $stderr.puts format("\n%s\n\n", lines.join("\n"))
  $stderr.print title.sub(/:?$/,': ')

  selection = Integer $stdin.readline(:chomp => true)
  unless (1..res.length).include?(selection)
    $stderr.puts 'Out of range'
    return menu(res, title)
  end
  return res[selection - 1]
rescue ArgumentError, Interrupt, EOFError
  quit
end

# Search the snippets directory for query using Spotlight (mdfind)
def search_spotlight(query, folder, first_try: true)
  # First try only search by filenames
  nameonly = first_try ? '-name ' : ''
  matches = %x{mdfind -onlyin "#{folder}" #{nameonly}'#{query}'}.strip

  results = matches.split("\n").map do |line|
    { title: File.basename(line, '.*'), path: line }
  end

  if results.empty? && first_try
      # if no results on the first try, try again searching all text
      return search_spotlight(query, folder, first_try: false)
  end

  results
end

# Search the snippets directory for query using find and grep
def search(query, folder, first_try: true)
  # First try only search by filenames

  cmd = if first_try
          %Q{find "#{folder}" -iregex '^#{Regexp.escape(folder)}/#{query.rx}' -and -not -name '.*' }
        else
          %Q{grep -iEl '#{query.rx}' "#{folder}/"*}
        end

  results = %x{#{cmd}}.lines(chomp: true).map do |path|
    { title: File.basename(path, '.*'), path: path }
  end

  # if no results on the first try, try again searching all text
  results.empty? && first_try ? search(query, folder, first_try: false) : results
end

def parse_options
  options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename(__FILE__)} [options] query"

    opts.on('-h', '--help', 'Display this screen') do
      puts optparse
      Process.exit 0
    end

    # Set defaults.
    options[:interactive] = true
    options[:launchbar] = false
    options[:output] = 'raw'
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
  if options.fetch(:launchbar) && STDIN.stat.size > 0
    STDIN.read.force_encoding('utf-8')
  else
    ARGV.join(' ')  # If ARGV is empty, so is the query.
  end
end

def validate_query!(query, optparse)
  if query.strip.empty?
    puts 'No search query'
    puts optparse
    Process.exit 1
  end
end

def build_launchbar_output(results)
  results.map do |result|
    title, path = result.values_at(:title, :path)
    snippets = IO.read(path).snippets
    next if snippets.empty?

    children = snippets.map do |snippet|
      {
        title: snippet.fetch(:title),
        quickLookURL: %Q{file://#{path}},
        action: 'pasteIt',
        actionArgument: snippet.fetch(:code),
        label: 'Paste'
      }
    end

    {
      title: title,
      quickLookURL: %Q{file://#{path}},
      children: children
    }
  end
end

options, help_message = parse_options()
query = CGI.unescape(construct_query(options))
validate_query!(query, help_message)
results = search(query, options.fetch(:source))

# No results.
if results.empty?
  if options.fetch(:launchbar)
    out = { title: 'No matching snippets found' }.to_json
    $stdout.puts out
  else
    $stderr.puts 'No results'
  end
  Process.exit 0
end

# At least some results.
if options.fetch(:launchbar)
  puts build_launchbar_output(results).to_json
elsif !options.fetch(:interactive)
  snippets = IO.read(results.first.fetch(:path)).snippets
  code_only = snippets.map { |s| s.fetch(:code) }
  output = options.fetch(:output) == 'json' ? snippets.to_json : code_only
  $stdout.puts output
else
  chosen_file = menu(results, 'Select a file')
  snippets = IO.read(chosen_file.fetch(:path)).snippets

  if snippets.empty?
    $stderr.puts 'No snippets found'
    Process.exit 0
  end

  chosen_snippet = menu(snippets, 'Select snippet')
  $stdout.puts chosen_snippet.fetch(:code)
end
