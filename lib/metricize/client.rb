class Metricize

  def increment(name, options = {})
    count = options.delete(:by) || 1
    enqueue_count(name, count, options)
  end

  def measure(name, value, options = {})
    enqueue_value(name, value, options)
  end

  def time(name, options = {})
    raise ArgumentError, "must be invoked with a block to time" unless block_given?
    start_time = Time.now
    block_result = yield
    measure(name + '.time', time_delta_ms(start_time))
    return block_result
  end

  private

  def enqueue_count(name, count, options)
    push_to_queue(build_metric_name(name) + '.count', count, options)
  end

  def enqueue_value(name, value, options)
    raise ArgumentError, "no numeric value provided in measure call" unless value.kind_of?(Numeric)
    value = (value*100.0).round / 100.0
    push_to_queue(build_metric_name(name), value, options)
  end

  def push_to_queue(name, value, options)
    raise RuntimeError, "#{self.class} server not running; try calling start on the instance first" unless @thread
    @queue << prepare_metric(name, value, options)
  end

  def build_metric_name(name)
    @prefix + '.' + sanitize(name)
  end

  def prepare_metric(name, value, options)
    options[:source] = sanitize(options[:source]) if options[:source]
    log_message "preparing metric: #{name}:#{value}:#{options}"
    options.merge(:name => name, :value => value)
  end

  def sanitize(name)
    name.to_s.strip.downcase.gsub(' ', '_').gsub(/[^a-z0-9._]/, '')
  end

  def time_delta_ms(start_time)
    ((Time.now - start_time) * 1000.0).to_i
  end

end
