module Metricize
  class Forwarder
    include Metricize::SharedMethods

    def initialize(options)
      @password          = options.fetch(:password)
      @username          = options.fetch(:username)
      @remote_url        = options[:remote_url]     || 'metrics-api.librato.com/v1/metrics'
      @remote_timeout    = options[:remote_timeout] || 10
      establish_logger(options)
      initialize_redis(options)
      establish_redis_connection
    end

    def go!
      process_metric_queue
    end

    private

    def process_metric_queue
      with_error_handling do
        queue = retrieve_queue_contents
        return if queue.empty?
        store_metrics(add_aggregate_info(queue))
        clear_queue
      end
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
        with_error_handling do
          print_histogram(key, values)
        end
        gauges << add_stat_by_key(key, values.size, '.count').merge(counter_attributes)
        gauges << add_stat_by_key(key, values.max, ".max")
        gauges << add_stat_by_key(key, values.min, ".min")
        [0.25, 0.50, 0.75, 0.95].each do |p|
          percentile = values.extend(Stats).calculate_percentile(p)
          gauges << add_stat_by_key(key, percentile, ".#{(p*100).to_i}e")
        end
      end
      gauges << add_stat_by_key(@queue_name + '.measurements', value_groups.size)
      gauges
    end

    def print_histogram(name, values)
      return if values.size < 5

      num_bins = [25, values.size].min.to_f
      bin_width = (values.max - values.min)/num_bins
      bin_width = 1 if bin_width == 0

      bins = (values.min...values.max).step(bin_width).to_a
      freqs = bins.map {| bin | values.select{|x| x >= bin && x <= (bin+bin_width) }.count }

      name = name.gsub('|','.').sub(/\.$/, '')

      values.extend(Stats)
      chart_data    = bins.map!(&:floor).zip(freqs)
      chart_options = { :bar       => true,
                        :title     => "\nHistogram for #{name} at #{Time.now}",
                        :hide_zero => true }
      chart_output  = AsciiCharts::Cartesian.new(chart_data, chart_options).draw +
                       "\n#{name}.count=#{values.count}\n" +
                       "#{name}.min=#{round(values.min, 2)}\n" +
                       "#{name}.max=#{round(values.max, 2)}\n" +
                       "#{name}.mean=#{round(values.mean, 2)}\n" +
                       "#{name}.stddev=#{round(values.standard_deviation, 2)}\n"
      log_message(chart_output, :info)
    end

    def add_stat_by_key(key, value, suffix = "")
      metric = { :name         => key.split('|')[0] + suffix,
                 :value        => value }
      metric.merge!(:source => key.split('|')[1]) if key.split('|')[1]
      metric
    end

  end
end
