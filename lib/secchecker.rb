require "secchecker/version"
require "yaml"
require "optparse"
require 'find'
require 'fileutils'

module Secchecker
  class Error < StandardError; end

  class Config
    def initialize(config)
      @config = config
      @patterns = config_value("patterns", false) || []
      @allowed = config_value("allowed", false) || []
    end
    attr_reader :patterns, :allowed

    def match_patterns(line)
      begin
        @patterns.each do |pat|
          return pat if pat =~ line
        end
      rescue
#        puts $!
      end
      nil
    end

    def match_allowed(line)
      @allowed.each do |pat|
        return pat if pat =~ line
      end
      nil
    end

    def unmatch_allowd(line)
    end
    
    private
    def config_value(key, require)
      value = @config[key]
      if require && (value.nil? || value.empty?)
        raise RuntimeError, "{key}: is empty"
      end
      value
    end
  end

  class MatchLine
    def initialize(line, lineno, pattern)
      @line = line
      @lineno = lineno
      @pattern = pattern
    end
    attr_reader :line, :lineno, :pattern
  end
  
  class Command
    def self.run(argv)
      STDOUT.sync = true
      opts = {}
      opt = OptionParser.new(argv)
      opt.version = VERSION
      opt.banner = "Usage: #{opt.program_name} [-h|--help] <dir>"
      opt.separator('')
      opt.separator("Examples:")
      opt.separator("    #{opt.program_name} ~/project")
      opt.separator('')      
      opt.separator("Options:")
      opt.on_head('-h', '--help', 'Show this message') do |v|
        puts opt.help
        exit       
      end
      opt.on('-s SETTINGFILE', '--setting=SETTINGFILE', 'setting file') {|v| opts[:s] = v}
#      commands = ['scan']
#      opt.on('-c COMMAND', '--command=COMMAND', commands, commands.join('|')) {|v| opts[:c] = v}
      opt.on('-v', '--verbose', 'verbose message') {|v| opts[:v] = v}
      opt.on('--dry-run', 'message only') {|v| opts[:dry_run] = v}
      opt.on('-a', '--all', 'check all files') {|v| opts[:a]}
      opt.parse!(argv)

      settings = opts[:s] || File.expand_path("~/.seccheckerrc")
      unless FileTest.file?(settings)
        puts opt.help
        exit
      end
      config = Config.new(YAML.load_file(settings))
      command = Command.new(opts, config)
      dir = argv[0]
      if dir.nil? || !FileTest.directory?(dir)
        puts opt.help
        exit        
      end
      command.run(dir)
    end

    def initialize(opts, config)
      @opts = opts
      @config = config
    end

   
    def run(dir)
      puts "secchecker #{dir}"
      dir = File.expand_path(dir)
      all_matchlines = []
      Dir.chdir(dir) do
        ls_files(dir) do |f|
          matchlines = process_file(dir, f)
          if matchlines.size > 0
            all_matchlines << matchlines 
          end
        end
      end
      if all_matchlines.size > 0
        puts ""
        puts "[ERROR] Matched one or more prohibited patterns"
        puts ""        
      end
    end

    private
    def git_repository?(dir)
      system('git rev-parse')
#      r = `git rev-parse --is-inside-work-tree`
#      r =~ 'true'
#      repodir = File.join(dir, ".git")
#      puts repodir
#      FileTest.directory?(repodir)
    end
    
    def ls_files(dir)
      if git_repository?(dir) && !@opts[:a]
        `git ls-files`.each_line do |f|
          f.chomp!
          yield f
        end
      else                        
        Find.find('.') {|f|
          yield f
        }
      end
    end

    def process_file(dir, f)
      path = File.expand_path(File.join(dir, f))
      return [] unless FileTest.file?(path)
      if is_file_binary(path)
        puts "skip binary file: #{path}" if @opts[:v]
        return []
      end
      puts "#{path}" if @opts[:v]

      
      matchlines = check_pattern(f)
      if matchlines.size > 0
        matchlines.each do |ml|
          puts "#{f}:#{ml.lineno}:#{ml.line}\##### #{ml.pattern} #####"
        end
      end       
      matchlines
    end

    
    def check_pattern(filename)
#      puts filename
      matchlines = []     
      lines = IO.readlines(filename, mode: "r:utf-8")
      lines.each_with_index do |line, index|
        line.chomp!
        pat = @config.match_patterns(line)
        if pat  && !@config.match_allowed(line)
          matchlines << MatchLine.new(line, index + 1, pat)
        end
      end
      matchlines
    end

    def is_file_binary(file)
      s = (File.read(file, File.stat(file).blksize) || "").split(//)
      ((s.size - s.grep(" ".."~").size) / s.size.to_f) > 0.30      
    end
  end
end
