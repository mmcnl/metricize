module Metricize
  class Forwarder
    include Metricize::SharedMethods

    def initialize(options)
      @password          = options.fetch(:password)
      @username          = options.fetch(:username)
      @remote_url        = options[:remote_url]     || 'metrics-api.librato.com/v1/metrics'
      @remote_timeout    = options[:remote_timeout] || 10
      @batch_size        = options[:batch_size] || 5000
      establish_logger(options)
      initialize_redis(options)
    end

    def go!
      process_metric_queue
    end

    private

    def process_metric_queue
      with_error_handling do
        queue = lshift_queue
        return if queue.empty?
        store_metrics(add_aggregate_info(queue))
      end
    end

    def lshift_queue
      return [] unless queue_length > 0
      current_batch = @redis.lrange(@queue_name, 0, @batch_size - 1)
      # ltrim indexes are 0 based and somewhat confusing -- see http://redis.io/commands/ltrim
      @redis.ltrim(@queue_name, 0, -1-@batch_size)
      current_batch.map {|metric| JSON.parse(metric, :symbolize_names => true) }
    end

    def queue_length
      log_message "queue_length=#{length = @redis.llen(@queue_name)}", :info
      length
    end

    def clear_queue
      log_message "clearing queue"
      @redis.del @queue_name
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
        [0.50, 0.95].each do |p|
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
