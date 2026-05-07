
# this is bash
# it has a space in the ruby command, so we need to do some tricks
# \
exec "/Applications/Sonic Pi.app/Contents/Resources/app/server/native/ruby/bin/ruby" -x $0 "$@"

#!/usr/bin/env ruby
require 'io/console'
require 'monitor'
require 'open3'
require "/Applications/Sonic Pi.app/Contents/Resources/app/server/ruby/lib/sonicpi/osc/osc"
require "/Applications/Sonic Pi.app/Contents/Resources/app/server/ruby/paths"
require "/Applications/Sonic Pi.app/Contents/Resources/app/server/ruby/lib/sonicpi/promise"

module SonicPi
  class Player
    def initialize(file, verbose: false)
      @file = File.expand_path(file)
      @verbose = verbose
      @show_errors = true
      @last_mtime = nil
      @server_started_prom = Promise.new
      @supercollider_started_prom = Promise.new
      @print_monitor = Monitor.new

      abort "File not found: #{@file}" unless File.exist?(@file)

      # Start daemon (clear gem env to avoid host gem warnings breaking port parsing)
      daemon_env = {"GEM_PATH" => nil, "GEM_HOME" => nil}
      daemon_stdin, daemon_stdout_and_err, daemon_wait_thr = Open3.popen2e(daemon_env, Paths.ruby_path, Paths.daemon_path)
      puts_c "Daemon started (pid #{daemon_wait_thr.pid})", :cyan
      puts_c "Logs: #{Paths.log_path}", :cyan

      daemon_info_prom = Promise.new
      Thread.new do
        daemon_stdout_and_err.each do |line|
          daemon_info_prom.deliver! line.force_encoding("UTF-8")
          Thread.current.kill
        end
      end

      daemon_info = daemon_info_prom.get.split.map(&:to_i)
      daemon_port              = daemon_info[0]
      gui_listen_to_spider_port = daemon_info[1]
      gui_send_to_spider_port  = daemon_info[2]
      @daemon_token            = daemon_info[7]

      # Keep daemon alive, kill on exit
      @daemon_client = OSC::UDPClient.new("localhost", daemon_port)
      at_exit do
        puts_c "\nShutting down...", :red
        @daemon_client.send("/daemon/exit", @daemon_token)
      end
      Thread.new { loop { @daemon_client.send("/daemon/keep-alive", @daemon_token); sleep 5 } }

      # OSC client for sending code
      @eval_client = OSC::UDPClient.new("localhost", gui_send_to_spider_port)

      # OSC server for receiving logs
      osc_server = OSC::UDPServer.new(gui_listen_to_spider_port)
      add_osc_handlers!(osc_server)

      # Wait for server boot
      puts_c "Waiting for Sonic Pi...", :cyan
      Thread.new do
        until @server_started_prom.delivered?
          begin
            @eval_client.send("/ping", @daemon_token, "Hello")
          rescue Errno::ECONNREFUSED
          end
          sleep 0.5
        end
      end

      @server_started_prom.get
      @supercollider_started_prom.get
      puts_c "Ready!", :green
      @eval_client.send("/mixer-amp", @daemon_token, 0.3, 1)

      # Initial run
      run_file

      # Main loop
      puts_c help_text.gsub(/\n/,"\r\n"), :cyan
      run_loop
    end

    def run_file
      code = File.read(@file)
      @eval_client.send("/run-code", @daemon_token, code)
      @last_mtime = File.mtime(@file)
      puts_c ">>> Loaded #{File.basename(@file)}", :green
    rescue => e
      puts_c "Error reading file: #{e.message}", :red
    end

    def toggle
      if @stopped
        run_file
        @stopped = false
      else
        stop
        @stopped = true
      end
    end

    def stop
      @eval_client.send("/stop-all-jobs", @daemon_token)
      puts_c ">>> Stopped", :yellow
    end

    def send_cue(n)
      @eval_client.send("/run-code", @daemon_token, "cue :key, n: #{n}")
    end

    def run_loop
      loop do
        # Wait for keypress or timeout (for file check)
        if IO.select([$stdin], nil, nil, 0.3)
          ch = $stdin.read_nonblock(1) rescue nil
          case ch
          when 'r'      then run_file
          when '.'      then toggle
          when 'l'      then @verbose = !@verbose; puts_c "Logs: #{@verbose ? 'on' : 'off'}", :cyan
          when 'e'      then @show_errors = !@show_errors; puts_c "Errors: #{@show_errors ? 'on' : 'off'}", :cyan
          when '?', 'h' then puts_c help_text, :cyan
          when 'q'      then break
          when '0'..'9' then send_cue(ch.to_i)
          end
        end

        # Check if file changed
        check_file
      end
    end

    def check_file
      mtime = File.mtime(@file)
      if @last_mtime && mtime > @last_mtime
        run_file
      end
    rescue Errno::ENOENT
      # file temporarily gone during save
    end

    def help_text
      <<~HELP

        Watching: #{File.basename(@file)}
        Keys: r reload | . stop | l logs | e errors | q quit
      HELP
      .gsub("\n","\r\n")
    end

    # --- OSC handlers ---

    def add_osc_handlers!(osc)
      osc.add_method("/log/multi_message") do |msg|
        next unless @verbose && msg.is_a?(Array)
        print_multi_message(msg)
      end

      osc.add_method("/log/info") do |msg|
        next unless @verbose
        puts_c "=> #{clean_text(msg[1])}", :blue
      end

      osc.add_method("/error") do |msg|
        next unless @show_errors
        job_id, description, trace, line_number = msg
        puts_c "Error line #{line_number} (run #{job_id})", :red
        puts_c "  #{description}", :red
        puts_c "  #{trace}", :red
      end

      osc.add_method("/syntax_error") do |msg|
        next unless @show_errors
        job_id, description, error_line, line_number = msg
        puts_c "Syntax error line #{line_number} (run #{job_id})", :magenta
        puts_c "  #{error_line}", :magenta
        puts_c "  #{description}", :magenta
      end

      osc.add_method("/scsynth/info") do |msg|
        @supercollider_started_prom.deliver! true
      end

      osc.add_method("/ack") do
        @server_started_prom.deliver! true
      end

      osc.add_method("/runs/all-completed") { }
      osc.add_method("/exited") { puts_c "Sonic Pi exited", :red }
    end

    def error?(text)
      text.to_s.match?(/skipping/)
    end

    def clean_text(text)
      text.to_s
        .gsub("/Applications/Sonic Pi.app/Contents/Resources/etc/samples","")
        .gsub(/"",\s*"/,'"')
        .gsub(/\n/, "\r\n")
    end

    def print_multi_message(msg)
      job_id, thread_name, time, size = msg[0..3]
      pairs = msg[4..].each_slice(2).to_a

      header = thread_name == "\"\"" ? "Run #{job_id}, Time #{time}" : "Run #{job_id}, #{thread_name}, Time #{time}"
      puts_c header, :bold
      pairs.each_with_index do |(colour, text), i|
        clean_text = clean_text(text)
        prefix = i < pairs.size - 1 ? "  ├─ " : "  └─ "
        puts_c "#{prefix}#{clean_text}", error?(clean_text) ? :red : :blue
      end
    end

    # --- Output ---

    def puts_c(msg, colour = :white)
      @print_monitor.synchronize do
        line = case colour
        when :red     then "\e[31m#{msg}\e[0m"
        when :green   then "\e[32m#{msg}\e[0m"
        when :yellow  then "\e[33m#{msg}\e[0m"
        when :blue    then "\e[34m#{msg}\e[0m"
        when :magenta then "\e[35m#{msg}\e[0m"
        when :cyan    then "\e[36m#{msg}\e[0m"
        when :bold    then "\e[1m#{msg}\e[22m"
        else               msg.to_s
        end
        $stdout.write "#{line}\r\n"
      end
    end
  end
end

verbose = ARGV.delete("--verbose")
if ARGV.empty? || ARGV[0] == "-h" || ARGV[0] == "--help"
  puts "Usage: play.rb [--verbose] <filename.rb>"
  puts ""
  puts "Starts Sonic Pi, loads the file, and reloads on save."
  puts "Keys: r reload | . stop | l logs | e errors | q quit"
  exit
end

$stdin.raw!
at_exit { $stdin.cooked! }

SonicPi::Player.new(ARGV[0], verbose: !!verbose)
