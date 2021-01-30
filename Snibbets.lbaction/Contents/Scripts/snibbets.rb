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
    return self.scan(/^#+/).length > 1
  end

  # Is the snippet in this block fenced?
  def fenced?
    count = self.scan(/^```/).length
    return count > 1 && count.even?
  end

  def rx
    return ".*" + self.gsub(/\s+/,'.*') + ".*"
  end

  # remove outside comments, fences, and indentation
  def clean_code
    block = self

    # if it's a fenced code block, just discard the fence and everything
    # outside it
    if block.fenced?
      return block.gsub(/(?:^|.*?\n)(`{3,})(\w+)?(.*?)\n\1.*/m) {|m| $3.strip }
    end

    # assume it's indented code, discard non-indented lines and outdent
    # the rest
    indent = nil
    inblock = false
    code = []
    block.split(/\n/).each {|line|
      if line =~ /^\s*$/ && inblock
        code.push(line)
      elsif line =~ /^( {4,}|\t+)/
        inblock = true
        indent ||= Regexp.new("^#{$1}")
        code.push(line.sub(indent,''))
      else
        inblock = false
      end
    }
    code.join("\n")
  end

  # Returns an array of snippets. Single snippets are returned without a
  # title, multiple snippets get titles from header lines
  def snippets
    content = self.dup

    # Split content by ATX headers. Everything on the line after the #
    # becomes the title, code is gleaned from text between that and the
    # next ATX header (or end)
    sections = []
    parts = content.split(/^#+/)[1..]

    parts.each {|p|
      lines = p.split(/\n/)
      title = lines.shift.strip.sub(/[.:]$/,'')
      block = lines.join("\n")
      code = block.clean_code
      if code && code.length > 0
        sections << {
          'title' => title,
          'code' => code.strip
        }
      end
    }
    return sections
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
    while line = $stdin.readline(:chomp => true)
      quit unless line =~ /^[0-9]/
      line = line.to_i
      if (line > 0 && line <= res.length)
        return res[line - 1]
      else
        $stderr.puts "Out of range"
        return menu(res,title)
      end
    end
  rescue Interrupt, EOFError => e
    quit
  end
end

# Search the snippets directory for query using Spotlight (mdfind)
def search_spotlight(query,folder,try=0)
  # First try only search by filenames
  nameonly = try > 0 ? '' : '-name '

  matches = %x{mdfind -onlyin "#{folder}" #{nameonly}'#{query}'}.strip

  results = matches.split(/\n/).map do |line|
    {
      'title' => File.basename(line, '.md'),
      'path' => line
    }
  end

  if results.empty? && try == 0
      # if no results on the first try, try again searching all text
      return search_spotlight(query,folder,1)
  end

  return results
end

# Search the snippets directory for query using find and grep
def search(query,folder,try=0)
  # First try only search by filenames

  if try > 0
    cmd = %Q{grep -iEl '#{query.rx}' "#{folder}/"*}
  else
    escaped_folder = Regexp.escape(folder)
    cmd = %Q{find "#{folder}" -iregex '^#{escaped_folder}/#{query.rx}'}
  end

  matches = %x{#{cmd}}.strip

  results = matches.split(/\n/).map do |line|
    {
      'title' => File.basename(line,'.*'),
      'path' => line
    }
  end

  if results.empty? && try == 0
    # if no results on the first try, try again searching all text
    return search(query,folder,1)
  end

  return results
end


options = {}

optparse = OptionParser.new do|opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} [options] query"
  # opts.on( '-l', '--launchbar', 'Format results for use in LaunchBar') do
  #   options[:launchbar] = true
  # end
  options[:interactive] = true
  opts.on( '-q', '--quiet', 'Skip menus and display first match') do
    options[:interactive] = false
    options[:launchbar] = false
  end
  options[:launchbar] = false
  options[:output] = "raw"
  opts.on( '-o', '--output FORMAT', 'Output format (launchbar or raw)' ) do |outformat|
    valid = %w(json launchbar lb raw)
    if outformat.downcase =~ /(launchbar|lb)/
      options[:launchbar] = true
      options[:interactive] = false
    else
      options[:output] = outformat.downcase if valid.include?(outformat.downcase)
    end
  end
  options[:source] = File.expand_path($search_path)
  opts.on('-s', '--source FOLDER', 'Snippets folder to search') do |folder|
    options[:source] = File.expand_path(folder)
  end
  opts.on("-h","--help",'Display this screen') do
    puts optparse
    Process.exit 0
  end
end

optparse.parse!

query = ''

if options[:launchbar]
  if STDIN.stat.size >0
    query = STDIN.read.force_encoding('utf-8')
  else
    query = ARGV.join(" ")
  end
else
  if ARGV.length
    query = ARGV.join(" ")
  end
end

query = CGI.unescape(query)

if query.strip.empty?
  puts "No search query"
  puts optparse
  Process.exit 1
end

results = search(query,options[:source])

if options[:launchbar]
  if results.length == 0
    out = {
      'title' => "No matching snippets found"
    }.to_json
    puts out
    Process.exit
  end

  output = results.map do |result|
    input = IO.read(result['path'])
    snippets = input.snippets
    next if snippets.length == 0

    children = snippets.map do |s|
      {
        'title' => s['title'],
        'quickLookURL' => %Q{file://#{result['path']}},
        'action' => 'pasteIt',
        'actionArgument' => s['code'],
        'label' => 'Paste'
      }
    end

    {
      'title' => result['title'],
      'quickLookURL' => %Q{file://#{result['path']}},
      'children' => children
    }
  end

  puts output.to_json
else
  if results.length == 0
    $stderr.puts "No results"
    Process.exit 0
  elsif results.length == 1 || !options[:interactive]
    input = IO.read(results[0]['path'])
  else
    answer = menu(results,"Select a file")
    input = IO.read(answer['path'])
  end


  snippets = input.snippets

  if snippets.length == 0
    $stderr.puts "No snippets found"
    Process.exit 0
  elsif snippets.length == 1 || !options[:interactive]
    if options[:output] == 'json'
      $stdout.puts snippets.to_json
    else
      snippets.each {|snip|
        $stdout.puts snip['code']
      }
    end
  elsif snippets.length > 1
    answer = menu(snippets,"Select snippet")
    $stdout.puts answer['code']
  end
end
