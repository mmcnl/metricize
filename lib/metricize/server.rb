class Metricize

  def initialize(options)
    @password      = options.fetch(:password)
    @username      = options.fetch(:username).sub('@','%40')
    @prefix        = options.fetch(:prefix)
    @send_interval = (options[:send_interval] || 60).to_f
    @logger        = options[:logger]         || Logger.new(STDOUT)
    @remote_url    = options[:remote_url]     || 'metrics-api.librato.com/v1/metrics'
    @timeout       = options[:timeout]        || 5
  end

  def start
    log_message "starting Metricize server", :info
    reset_queue
    @thread ||= Thread.fork do
      loop do
        wait_for_clients_to_send_metrics
        process_metric_queue
      end
    end
  end

  def stop
    log_message "stopping Metricize server", :info
    @thread.kill if @thread
    @thread = nil
  end

  def send!
    process_metric_queue
  end

  private

  def reset_queue
    @queue = { :gauges => [], :counters => [] }
  end

  def wait_for_clients_to_send_metrics
    sleep @send_interval
  end

  def process_metric_queue
    log_message "checking queue"
    return if (@queue[:gauges].empty? && @queue[:counters].empty?)

    store_metrics(add_aggregate_info(@queue.clone))
    reset_queue
  rescue StandardError => e
    log_message "Error: " + e.message, :error
  end

  def log_message(message, level = :debug)
    message = "[Metricize #{Process.pid}] " + message
    @logger.send(level, message)
  end

  def store_metrics(data)
    log_message "sending {counters: #{@queue[:counters].size} gauges: #{@queue[:gauges].size}}", :info
    log_message "sending: #{data}"
    start_time = Time.now
    RestClient.post("https://#{@username}:#{@password}@#{@remote_url}",
                    data.to_json,
                    :timeout      => @timeout,
                    :content_type => 'application/json')
    log_message "request completed in #{time_delta_ms(start_time)}ms"
  end

  def add_aggregate_info(data)
   counters = consolidate_counts(data[:counters].clone)
   data = { :gauges => add_value_stats(data[:gauges].clone, counters)}
   data.merge!(:counters => counters)
   data.delete_if {|k,v| v.empty? }
  end

  def consolidate_counts(counters)
    aggregated_counts = {}
    counters.each_with_index do |metric,i|
      key = [metric.fetch(:name), metric[:source]].join('|') # temporarily group by name+source
      aggregated_counts[key] = aggregated_counts[key].to_i + metric[:value]
      counters[i] = nil # set consolidated stat to nil for removal later via compact
    end
    aggregated_counts.map do | key, count |
      add_stat_by_key(key, count)
    end
  end

  def add_value_stats(gauges, counters)
    value_groups = {}
    gauges.each do | metric |
      key = [metric.fetch(:name), metric[:source]].join('|')
      value_groups[key] ||= []
      value_groups[key] << metric[:value]
    end
    value_groups.each do |key, values|
      counters << add_stat_by_key(key, values.size, '.count')
      gauges << add_stat_by_key(key, values.max, ".max")
      gauges << add_stat_by_key(key, values.min, ".min")
      gauges << add_stat_by_key(key, calculate_percentile(values, 0.5), ".median")
      [0.95, 0.90, 0.75].each do |p|
        percentile = calculate_percentile(values, p)
        gauges << add_stat_by_key(key, percentile, ".#{(p*100).to_i}e")
      end
    end
    gauges
  end

  def add_stat_by_key(key, value, suffix = "")
      metric = { :name         => key.split('|')[0] + suffix,
                 :value        => value,
                 :measure_time => Time.now.to_i }
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
