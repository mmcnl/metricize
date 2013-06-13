module Metricize
  class Client
    include SharedMethods

    def initialize(options = {})
      @prefix = options[:prefix]
      establish_logger(options)
      initialize_redis(options)
      establish_redis_connection
    end

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
      value = (value*10000.0).round / 10000.0
      push_to_queue(build_metric_name(name), value, options)
    end

    def push_to_queue(name, value, options)
      data = prepare_metric(name, value, options).to_json
      log_message "redis_data_sent='#{data}'"
      start_time = Time.now
      @redis.lpush(@queue_name, data)
      log_message "redis_request_duration_ms=#{time_delta_ms(start_time)}"
    end

    def build_metric_name(name)
      [ @prefix, sanitize(name) ].compact.join('.')
    end

    def sanitize(name)
      name.to_s.strip.downcase.gsub(' ', '_').gsub(/[^a-z0-9._]/, '')
    end

    def prepare_metric(name, value, options)
      options[:source] = sanitize(options[:source]) if options[:source]
      options.merge(:name => name, :value => value)
    end

  end
end
