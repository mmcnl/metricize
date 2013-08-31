module Metricize
  module SharedMethods

    def establish_redis_connection
      log_message "metricize_version=#{VERSION} connecting to Redis at #{@queue_host}:#{@queue_port}", :info
      with_error_handling do
        @redis = Redis.connect(:host => @queue_host, :port => @queue_port)
        @redis.ping
      end
    end

    private

    def initialize_redis(options)
      @queue_host  = options[:queue_host] || '127.0.0.1'
      @queue_port  = options[:queue_port] || 6379
      @queue_name  = options[:queue_name] || 'metricize_queue'
      establish_redis_connection
    end

    def establish_logger(options)
      @logger = options[:logger] || Logger.new(STDOUT)
    end

    def log_message(message, level = :debug)
      message = "[#{self.class} #{Process.pid}] " + message
      @logger.send(level.to_sym, message)
    end

    def time_delta_ms(start_time)
      (((Time.now - start_time) * 100000.0).round) / 100.0
    end

    def round(value, num_places)
      factor = 10.0**num_places
      ((value * factor).round) / factor
    end

    def with_error_handling
      yield
    rescue StandardError => e
      log_message %Q(#{e.class}:#{e.message}\n#{e.backtrace.join("\n")}), :error
    end

  end
end

