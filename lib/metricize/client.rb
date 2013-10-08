module Metricize
  class Client
    include SharedMethods

    def initialize(options = {})
      @prefix = options[:prefix]
      @log_sampling_ratio = options[:log_sampling_ratio] || 0.10
      establish_logger(options)
      initialize_redis(options)
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
      measure(name + '.time', time_delta_ms(start_time), options)
      return block_result
    end

    private

    def enqueue_count(name, count, options)
      push_to_queue(build_metric_name(name) + '.count', count, options)
    end

    def enqueue_value(name, value, options)
      raise ArgumentError, "no numeric value provided in measure call" unless value.kind_of?(Numeric)
      push_to_queue(build_metric_name(name), round(value, 4), options)
    end

    def push_to_queue(name, value, options)
      data = prepare_metric(name, value, options).to_json
      with_error_handling do
        @redis.lpush(@queue_name, data)
      end
      return unless rand < @log_sampling_ratio
      msg = "#{name.gsub('.', '_')}=#{value}" # splunk chokes on dots in field names
      msg << ", metric_source=#{options[:source].gsub('.', '_')}" if options[:source]
      log_message msg, :info
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
