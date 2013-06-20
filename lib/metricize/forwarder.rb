module Metricize
  class Forwarder
    include Metricize::SharedMethods

    def initialize(options)
      @password          = options.fetch(:password)
      @username          = options.fetch(:username)
      @remote_url        = options[:remote_url]     || 'metrics-api.librato.com/v1/metrics'
      @remote_timeout    = options[:remote_timeout] || 10
      @logger            = options[:logger]         || Logger.new(STDOUT)
      initialize_redis(options)
    end

    def go!
      establish_redis_connection
      process_metric_queue
    end

    private

    def process_metric_queue
      queue = retrieve_queue_contents
      return if queue.empty?
      store_metrics(add_aggregate_info(queue))
      clear_queue
    rescue RuntimeError => e
      log_message "Error: " + e.message, :error
    end

    def retrieve_queue_contents
      log_message "checking... queue_length=#{queue_length = @redis.llen(@queue_name)}", :info
      return [] unless queue_length > 0
      queue = @redis.lrange(@queue_name, 0, -1)
      queue.map {|metric| JSON.parse(metric, :symbolize_names => true) }
    end

    def clear_queue
      log_message "clearing queue"
      @redis.del @queue_name if @redis
    end

    def store_metrics(data)
      log_message "remote_data_sent='#{data}'"
      start_time = Time.now
      RestClient.post("https://#{@username.sub('@','%40')}:#{@password}@#{@remote_url}",
                      data.to_json,
                      :timeout      => @remote_timeout,
                      :content_type => 'application/json')
      log_message "remote_data_sent_chars=#{data.to_s.length}, remote_request_duration_ms=#{time_delta_ms(start_time)}", :info
    end

    def add_aggregate_info(metrics)
      counters, measurements = metrics.partition {|metric| metric.fetch(:name) =~ /.count$/ }
      counters = consolidate_counts(counters)
      measurements = add_value_stats(measurements)
      measurements << add_stat_by_key(@queue_name + '.counters', counters.size)
      { :gauges => counters + measurements, :measure_time => Time.now.to_i }
    end

    def consolidate_counts(counters)
      aggregated_counts = {}
      counters.each_with_index do |metric,i|
        # collect aggregate stats for each name+source combination
        key = [metric.fetch(:name), metric[:source]].join('|')
        aggregated_counts[key] = aggregated_counts[key].to_i + metric[:value]
      end
      aggregated_counts.map do | key, count |
        add_stat_by_key(key, count).merge(counter_attributes)
      end
    end

    def counter_attributes
      { :attributes => {:source_aggregate => true, :summarize_function => 'sum'} }
    end

    def add_value_stats(gauges)
      value_groups = {}
      gauges.each do | metric |
        key = [metric.fetch(:name), metric[:source]].join('|')
        value_groups[key] ||= []
        value_groups[key] << metric[:value]
      end
      value_groups.each do |key, values|
        print_histogram(key, values)
        gauges << add_stat_by_key(key, values.size, '.count').merge(counter_attributes)
        gauges << add_stat_by_key(key, values.max, ".max")
        gauges << add_stat_by_key(key, values.min, ".min")
        [0.25, 0.50, 0.75, 0.95].each do |p|
          percentile = calculate_percentile(values, p)
          gauges << add_stat_by_key(key, percentile, ".#{(p*100).to_i}e")
        end
      end
      gauges << add_stat_by_key(@queue_name + '.measurements', value_groups.size)
      gauges
    end

    def print_histogram(name, values)
      return if values.size < 5
      min = values.min.floor
      max = values.max.ceil
      range = (max - min).to_f

      num_bins = [25, values.size].min.to_f
      bin_width = (range/num_bins)
      bin_width = 1 if bin_width == 0

      bins = (min...max).step(bin_width).to_a
      freqs = bins.map {| bin | values.select{|x| x >= bin && x <= (bin+bin_width) }.count }

      mean = values.inject(:+).to_f / values.size
      mean = ((mean * 10.0).round) / 10.0

      name = name.gsub('|','.').sub(/\.$/, '')

      chart_data    = bins.map!(&:round).zip(freqs)
      chart_options = { :bar       => true,
                        :title     => "\nHistogram for #{name} at #{Time.now}",
                        :hide_zero => true }
      chart_output  = AsciiCharts::Cartesian.new(chart_data, chart_options).draw +
                     "\n#{name}.count=#{values.count}\n" +
                       "#{name}.min=#{values.min}\n" +
                       "#{name}.max=#{values.max}\n" +
                       "#{name}.mean=#{mean}\n"
      log_message(chart_output, :info)
    rescue => e
      log_message("#{e}: Could not print histogram for #{name} with these input values: #{values.inspect}", :error)
    end

    def add_stat_by_key(key, value, suffix = "")
      metric = { :name         => key.split('|')[0] + suffix,
                 :value        => value }
      metric.merge!(:source => key.split('|')[1]) if key.split('|')[1]
      metric
    end

    def calculate_percentile(values, percentile)
      return values.first if values.size == 1
      values_sorted = values.sort
      k = (percentile*(values_sorted.length-1)+1).floor - 1
      values_sorted[k]
    end

  end
end
