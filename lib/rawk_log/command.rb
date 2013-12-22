require 'date'
require 'rawk_log/stat'
require 'rawk_log/stat_hash'

module RawkLog
  class Command
    HELP = "\nRAWK - Rail's Analyzer With Klass\n"+
    "Created by Chris Hobbs of Spongecell, LLC\n"+
    "This tool gives statistics for Ruby on Rails log files. The times for each request are grouped and totals are displayed. "+
    "If process ids are present in the log files then requests are sorted by ActionController actions otherwise requests are grouped by url. "+
    "By default total request times are used for comparison but database time or render time can be used by specifying the correct flag. "+
    "The log file is read from standard input unless the -f flag is specified.\n\n"+
    "The options are as follows:\n\n"+
    "  -?  Display this help.\n\n"+
    "  -d  Use DB times as data points. These times are found after 'DB:' in the log file. This overrides the default behavior of using the total request time.\n\n"+
    "  -f <filename> Use the specified file instead of standard input.\n\n"+
    "  -h  Display this help.\n\n"+
    "  -r  Use Render times as data points. These times are found after 'Rendering:' in the log file. This overrides the default behavior of using the total request time.\n\n"+
    "  -s <count> Display <count> results in each group of data.\n\n"+
    "  -t  Test\n\n"+
    "  -u  Group requests by url instead of the controller and action used. This is the default behavior if there is are no process ids in the log file.\n\n"+
    "  -w <count> Display the top <count> worst requests.\n\n"+
    "  -x <date> Date (inclusive) to start parsing in 'yyyy-mm-dd' format.\n\n"+
          "  -y <date> Date (inclusive) to stop parsing in 'yyyy-mm-dd' format.\n\n"+
    "To include process ids in your log file, add this to application's Gemfile:\n\n"+
    "    gem 'rawk_log'\n\n"+
    "This software is Beerware, if you like it, buy yourself a beer or something nicer ;)\n"+
    "\n"+
    "Example usage:\n"+
    "    rawk_log log/production.log\n"
    
    def initialize(args)
      @start_time = Time.now
      build_arg_hash(args)
    end

    def run
      if @arg_hash.keys.include?("?") || @arg_hash.keys.include?("h")
        puts HELP
      elsif @arg_hash.keys.include?("t")
        Stat.test
      else
        init_args
        build_stats
        print_stats
      end
    end

    def build_arg_hash(args)
      @arg_hash = Hash.new
      last_key=nil
      for a in args
        if a.index("-")==0 && a.length>1
          a[1,1000].scan(/[a-z]|\?/).each {|c| @arg_hash[last_key=c]=nil}
          @arg_hash[last_key] = a[/\d+/] if last_key
        elsif a.index("-")!=0 && last_key
          @arg_hash[last_key] = a
        end
      end
      #$* = [$*[0]]
    end

    def init_args
      @sorted_limit=20
      @worst_request_length=20
      @force_url_use = false
      @db_time = false
      @render_time = false
      @input = $stdin
      keys = @arg_hash.keys
      @force_url_use = keys.include?("u")
      @db_time = keys.include?("d")
      @render_time = keys.include?("r")
      @worst_request_length=(@arg_hash["w"].to_i) if @arg_hash["w"]
      @sorted_limit = @arg_hash["s"].to_i if @arg_hash["s"]
      @input = File.new(@arg_hash["f"]) if @arg_hash["f"]
      @from =(Date.parse(@arg_hash["x"])) if @arg_hash["x"]
      @to =(Date.parse(@arg_hash["y"])) if @arg_hash["y"]
    end
    
    def is_id?(word)
      word =~ /^((\d+)|([\dA-F\-]{36}))$/i
    end
    
    def build_stats
      @stat_hash = StatHash.new
      @total_stat = Stat.new("All Requests")
      @worst_requests = []
      last_actions = Hash.new
      last_date = Date.civil
      while @input.gets
        if $_.index("Processing ")==0
          action = $_.split[1]
          pid = $_[/\(pid\:\d+\)/]
          date_string = $_[/(?:19|20)[0-9]{2}-(?:0[1-9]|1[012])-(?:0[1-9]|[12][0-9]|3[01])/]
          date = date_string ? Date.parse(date_string) : last_date
          last_date = date
          datetime = $_[/(?:19|20)[0-9]{2}-(?:0[1-9]|1[012])-(?:0[1-9]|[12][0-9]|3[01]) (?:[0-1][0-9]|2[0-3]):(?:[0-5][0-9]|60):(?:[0-5][0-9]|60)/].to_s
          last_actions[pid]=action if pid
          next
        end
        next unless $_.index("Completed in")==0
        pid = key = nil
        #get the pid unless we are forcing url tracking
        pid = $_[/\(pid\:\d+\)/] if !@force_url_use
        key = last_actions[pid] if pid
        time = 0.0
        
        # Old: Completed in 0.45141 (2 reqs/sec) | Rendering: 0.25965 (57%) | DB: 0.06300 (13%) | 200 OK [http://localhost/jury/proposal/312]
        # New:  Completed in 100ms (View: 40, DB: 4) 
        unless defined? @new_log_format
          @new_log_format = $_ =~ /Completed in \d+ms/ 
        end
        
        if @new_log_format
          if @db_time
            time_string = $_[/DB: \d+/]
          elsif @render_time
            time_string = $_[/View: \d+/]
          else
            time_string = $_[/Completed in \d+ms/]
          end
          time_string = time_string[/\d+/] if time_string
          time = time_string.to_i if time_string
        else
          if @db_time
            time_string = $_[/DB: \d+\.\d+/]
          elsif @render_time
            time_string = $_[/Rendering: \d+\.\d+/]
          else
            time_string = $_[/Completed in \d+\.\d+/]
          end
          time_string = time_string[/\d+\.\d+/] if time_string
          time = time_string.to_f if time_string
        end
        
        
        #if pids are not specified then we use the url for hashing
        #the below regexp turns "[http://spongecell.com/calendar/view/bob]" to "/calendar/view"
        unless key

          key = if @force_url_use
            ($_[/\[[^\]]+\]/].gsub(/\S+\/\/(\w|\.)*/,''))[/[^\?\]]*/]
          else
            data = $_[/\[[^\]]+\]/].gsub(/\S+\/\/(\w|\.)*/,'')
            s = data.gsub(/(\?.*)|\]$/,'').split("/")

            keywords = s.inject([]) do |keywords, word|
              if is_id?(word.to_s)
                keywords << '{ID}'
              elsif !word.to_s.empty?
                keywords << word.to_s
              end
              keywords
            end
            k = "/#{keywords.join("/")}"
          end
        end

        if (@from.nil? or @from <= date) and (@to.nil? or @to >= date) # date criteria here
          @stat_hash.add(key,time)
          @total_stat.add(time)
          if @worst_requests.length<@worst_request_length || @worst_requests[@worst_request_length-1][0]<time
            @worst_requests << [time,%Q(#{datetime} #{$_})]
            @worst_requests.sort! {|a,b| (b[0] && a[0]) ? b[0]<=>a[0] : 0}
            @worst_requests=@worst_requests[0,@worst_request_length]
          end
        end
      end
    end
    def print_stats
      title = "Log Analysis of #{@db_time ? 'DB' : @render_time ? 'render' : 'total'} request times#{@from ? %Q( from #{@from.to_s}) : ""}#{@to ? %Q( through #{@to.to_s}) : ""}"
      puts title
      puts "=" * title.size
      puts ""
      label_size = @stat_hash.print()
      puts "-" * label_size
      puts @total_stat.to_s(label_size)
      puts "\n\nTop #{@sorted_limit} by Count"
      @stat_hash.print(:sort_by=>"count",:limit=>@sorted_limit,:ascending=>false)
      puts "\n\nTop #{@sorted_limit} by Sum of Time"
      @stat_hash.print(:sort_by=>"sum",:limit=>@sorted_limit,:ascending=>false)
      puts "\n\nTop #{@sorted_limit} Greatest Max"
      @stat_hash.print(:sort_by=>"max",:limit=>@sorted_limit,:ascending=>false)
      puts "\n\nTop #{@sorted_limit} Greatest Median"
      @stat_hash.print(:sort_by=>"median",:limit=>@sorted_limit,:ascending=>false)
      puts "\n\nTop #{@sorted_limit} Greatest Avg"
      @stat_hash.print(:sort_by=>"average",:limit=>@sorted_limit,:ascending=>false)
      puts "\n\nTop #{@sorted_limit} Least Min"
      @stat_hash.print(:sort_by=>"min",:limit=>@sorted_limit)
      puts "\n\nTop #{@sorted_limit} Greatest Standard Deviation"
      @stat_hash.print(:sort_by=>"standard_deviation",:limit=>@sorted_limit,:ascending=>false)
      puts "\n\nTop #{@worst_request_length} Worst Requests"
      @worst_requests.each {|w| puts w[1].to_s}
      puts "\n\nCompleted report in %1.2f minutes" % ((Time.now.to_i-@start_time.to_i)/60.0)
    end
  end
end