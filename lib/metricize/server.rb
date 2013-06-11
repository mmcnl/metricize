module Metricize
  class Server
    include Metricize::SharedMethods
    def initialize(options)
      @remote_url        = options[:remote_url]        || 'metrics-api.librato.com/v1/metrics'
      @password          = options.fetch(:password)
      @username          = options.fetch(:username).sub('@','%40')
      @flush_interval    = (options[:flush_interval]   || 60).to_f
      @timeout           = options[:timeout]           || 10
      @logger            = options[:logger]            || Logger.new(STDOUT)
      @default_log_level = options[:default_log_level] || 'debug'
      establish_redis_connection(options)
    end

    def start
      log_message "starting Metricize server", :info
      loop do
        wait_for_clients_to_send_metrics
        process_metric_queue
      end
    ensure
      log_message "Metricize server stopped", :warn
    end

    def send!
      process_metric_queue
    end

    private

    def wait_for_clients_to_send_metrics
      sleep @flush_interval
    end

    def process_metric_queue
      queue = retrieve_queue_contents
      return if queue.empty?
      store_metrics(add_aggregate_info(queue))
      clear_queue
    rescue RuntimeError => e
      log_message "Error: " + e.message, :error
    end

    def retrieve_queue_contents
      log_message "checking queue"
      queue = @redis.lrange(REDIS_QUEUE_NAME, 0, -1)
      queue.map {|metric| JSON.parse(metric, :symbolize_names => true) }
    end

    def clear_queue
      log_message "clearing queue"
      @redis.del REDIS_QUEUE_NAME
    end

    def store_metrics(data)
      log_message "remote_data_sent_chars=#{data.to_s.length}", :info
      log_message "remote_data_sent='#{data}'"
      start_time = Time.now
      RestClient.post("https://#{@username}:#{@password}@#{@remote_url}",
                      data.to_json,
                      :timeout      => @timeout,
                      :content_type => 'application/json')
      log_message "remote_request_duration_ms=#{time_delta_ms(start_time)}"
    end

    def add_aggregate_info(metrics)
      counters, measurements = metrics.partition {|metric| metric.fetch(:name) =~ /.count$/ }
      counters = consolidate_counts(counters)
      measurements = add_value_stats(measurements)
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
        counter_attributes = { :attributes => {:source_aggregate => true, :summarize_function => 'sum'} }
        add_stat_by_key(key, count).merge(counter_attributes)
      end
    end

    def add_value_stats(gauges)
      value_groups = {}
      gauges.each do | metric |
        key = [metric.fetch(:name), metric[:source]].join('|')
        value_groups[key] ||= []
        value_groups[key] << metric[:value]
      end
      value_groups.each do |key, values|
        counter_attributes = { :attributes => {:source_aggregate => true, :summarize_function => 'sum'} }
        gauges << add_stat_by_key(key, values.size, '.count').merge(counter_attributes)
        gauges << add_stat_by_key(key, values.max, ".max")
        gauges << add_stat_by_key(key, values.min, ".min")
        [0.25, 0.50, 0.75, 0.95].each do |p|
          percentile = calculate_percentile(values, p)
          gauges << add_stat_by_key(key, percentile, ".#{(p*100).to_i}e")
        end
      end
      gauges
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
