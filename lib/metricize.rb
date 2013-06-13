require "metricize/version"

require 'thread'
require 'rest-client'
require 'json'
require 'logger'
require 'redis'

module Metricize

  module SharedMethods
    def establish_redis_connection
      log_message "connecting to Redis at #{@queue_host}:#{@queue_port}:#{@queue_name}", :info
      @redis = Redis.connect(:host => @queue_host, :port => @queue_port)
      log_message "queue_name=#{@queue_name}, queue_length=#{@redis.llen(@queue_name)}"
    end

    private

    def establish_logger(options)
      @logger            = options[:logger]            || Logger.new(STDOUT)
      @default_log_level = options[:default_log_level] || 'debug'
    end

    def initialize_redis(options)
      @queue_host  = options[:queue_host] || '127.0.0.1'
      @queue_port  = options[:queue_port] || 6379
      @queue_name  = options[:queue_name] || 'metricize_queue'
    end

    def log_message(message, level = @default_log_level)
      message = "[#{self.class} #{Process.pid}] " + message
      @logger.send(level.to_sym, message)
    end

    def time_delta_ms(start_time)
      (((Time.now - start_time) * 100000.0).round) / 100.0
    end

  end

  class NullClient
    def self.increment(*args); end
    def self.measure(*args); end
    def self.time(*args); yield; end
    def self.establish_redis_connection; end
  end

  class NullServer
    def self.start; end
    def self.send!; end
  end

end

require "metricize/server"
require "metricize/client"
