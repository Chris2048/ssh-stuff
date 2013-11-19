#!/usr/bin/env ruby

class SshConfigDuplicateError < StandardError; end

class SshConfig
  @@ssh_config = "#{ENV['HOME']}/.ssh/config"

  attr_accessor :host, :hostname, :user, :port, :idfile
  alias :to_s :host

  def initialize(host, hostname, user, port, idfile)
    @host = host
    @hostname = hostname
    @user = user
    @port = port
    @idfile = idfile
  end

  class << self
    protected :new

    def list
      lines = File.read(@@ssh_config).split("\n")

      entries = []
      current_entry = []

      lines << ""
      lines.each do |line|
        if line.strip.empty?
          entries << parse(current_entry) if current_entry.any?
          current_entry = []
        else
          current_entry << line
        end
      end

      entries
    end

    def add(args)
      host = args[:host]
      hostname = args[:hostname]
      user = args[:user] || "root"
      port = args[:port] || "22"
      idfile = args[:idfile]

      force = args[:force]

      if find_by_host(host).nil? || force
        delete(host)

        new_config = SshConfig.new(host, hostname, user, port, idfile)

        configs = list
        configs << new_config

        write(configs)

        new_config
      else
        raise SshConfigDuplicateError, "Can not overwrite existing record"
      end
    end

    def find_by_host(host)
      list.find { |c| c.host == host }
    end

    def empty!
      write([])
    end

    def delete(host)
      configs = list
      configs = configs.delete_if { |c| c.host == host }
      write(configs)
    end

    def write(configs)
      hosts = []

      configs.sort! { |a,b| a.host <=> b.host }
      configs.each do |c|
        hosts << "Host #{c.host}"
        hosts << "  HostName #{c.hostname}"
        hosts << "  User #{c.user}" if c.user
        hosts << "  Port #{c.port}" if c.port
        hosts << "  IdentityFile #{c.idfile}" if c.idfile
        hosts << ""
      end

      File.open(@@ssh_config, 'w') {|f| f.print hosts.join("\n") }
    end

    def parse(config)
      host = config.first[/Host (.*)/, 1]
      config_hash = {}

      config[1..-1].each do |entry|
        entry.strip!
        next if entry.empty?
        key, value = entry.strip.split(" ")
        config_hash[key.downcase] = value
      end

      SshConfig.new(host,
        config_hash['hostname'], config_hash['user'],
        config_hash['port'], config_hash['identityfile'])
    end

  end
end

def help_text(exit_code = 0)
  script_name = File.basename $0
  puts """USAGE: #{script_name} add <host> <hostname> [--user=<user>] [--port=<port>]
       #{script_name} modify <host> <hostname> [--user=<user>] [--port=<port>]
       #{script_name} delete <host>
       #{script_name} list
       #{script_name} empty
       #{script_name} export
       #{script_name} import <file>
"""
  exit(exit_code)
end

def parse(argv)
  argv.shift

  new_config = {
    :host => argv.shift,
    :hostname => argv.shift
  }

  if argv.size > 0
    argv.each do |arg|
      if arg =~ /--([a-z]+)=(.*)/
        new_config[$1.to_sym] = $2
      end
    end
  end

  new_config
end

if ARGV.size.zero? || ['-h', '--help', 'help'].include?(ARGV.first)
  help_text
else
  case ARGV[0]
  when 'add'
    if [3,4,5].include?(ARGV.size)
      begin
        new_config = parse(ARGV)

        config = SshConfig.add(new_config)
        puts "  [Adding] #{config.host} -> #{config.hostname}"
        exit 0
      rescue SshConfigDuplicateError
        $stderr.puts $!
        exit 3
      end
    else
      $stderr.puts "The add subcommand requires at least a host and a hostname.\n\n"
      help_text 2
    end
  when 'modify'
    if [3,4,5].include?(ARGV.size)
      new_config = parse(ARGV)
      new_config[:force] = true
      config = SshConfig.add(new_config)
      puts "  [Modifying] #{config.host} -> #{config.hostname}"
      exit 0
    else
      $stderr.puts "The modify subcommand requires at least a host and a hostname.\n\n"
      help_text 4
    end
  when 'delete', 'del', 'remove', 'rm'
    if ARGV.size == 2
      SshConfig.delete(ARGV[1])
      puts "  [Deleting] #{ARGV[1]}"
      exit 0
    else
      $stderr.puts "The delete subcommand requires a hostname.\n\n"
      help_text 2
    end

  when 'list'
    configs = SshConfig.list
    pad = configs.max{|a,b| a.to_s.length <=> b.to_s.length }.to_s.length

    puts "Listing #{configs.size} configs(s):"

    configs.each do |c|
      user = c.user ? "#{c.user}@" : ""
      puts "#{c.host.rjust(pad+2)} -> #{user}#{c.hostname}:#{c.port||22}"
    end
    exit 0
  when 'empty'
    print "  [Emptying] "
    SshConfig.empty!
    puts "Done."
    exit 0
  when 'export'
    configs = SshConfig.list
    configs.each do |c|
      puts "#{c.host},#{c.hostname},#{c.user},#{c.port}"
    end
    exit 0
  when 'import'
    if ARGV.size == 2
      begin
        File.foreach(ARGV[1]) do |line|
          cfg_infos = line.strip.split(',')
          hash = {
            :host => cfg_infos[0],
            :hostname => cfg_infos[1]
          }

          hash[:user] = cfg_infos[2] if cfg_infos.size > 2
          hash[:port] = cfg_infos[3] if cfg_infos.size > 3
          hash[:force] = true

          config = SshConfig.add(hash)

          puts "  [Adding] #{config.host} -> #{config.hostname}"
        end
        exit 0
      rescue
        $stderr.puts "Cannot import. A problem occured while opening the import file (#{$!.message})."
        exit 5
      end
    else
      $stderr.puts "The import command requires an input file.\n\n"
      help_text 6
    end
  else
    $stderr.puts "Invalid option: #{ARGV[0]}"
    help_text 1
  end
end
