require "metricize/version"

require 'thread'
require 'rest-client'
require 'json'
require 'logger'
require 'redis'

module Metricize

  REDIS_QUEUE_NAME = 'metrics_queue'

  module SharedMethods
    def establish_logger(options)
      @logger            = options[:logger]            || Logger.new(STDOUT)
      @default_log_level = options[:default_log_level] || 'debug'
    end

    def establish_redis_connection(options)
      @redis_host  = options[:redis_host] || '127.0.0.1'
      @redis_port  = options[:redis_port] || 6379
      log_message "connecting to Redis at #{@redis_host}:#{@redis_port}", :info
      @redis = Redis.new(:host => @redis_host, :port => @redis_port)
      log_message "redis_queue=#{REDIS_QUEUE_NAME},queue_length=#{@redis.llen(REDIS_QUEUE_NAME)}"
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
    def self.initialize(*args); end
    def self.increment(*args); end
    def self.measure(*args); end
    def self.time(*args); yield; end
  end
  class NullServer
    def self.initialize(*args); end
    def self.start; end
    def self.stop; end
    def self.send!; end
  end

end

require "metricize/server"
require "metricize/client"
