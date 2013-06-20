require "metricize/version"

require 'thread'
require 'rest-client'
require 'json'
require 'logger'
require 'redis'
require 'ascii_charts'

module Metricize
  module SharedMethods

    def establish_redis_connection
      log_message "metricize_version=#{VERSION} connecting to Redis at #{@queue_host}:#{@queue_port}", :info
      @redis = Redis.connect(:host => @queue_host, :port => @queue_port)
      @redis.ping
    end

    private

    def initialize_redis(options)
      @queue_host  = options[:queue_host] || '127.0.0.1'
      @queue_port  = options[:queue_port] || 6379
      @queue_name  = options[:queue_name] || 'metricize_queue'
    end

    def establish_logger(options)
      @logger            = options[:logger]            || Logger.new(STDOUT)
      @default_log_level = options[:default_log_level] || 'debug'
    end

    def log_message(message, level = :debug)
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

  class NullForwarder
    def self.go!; end
  end

end

require "metricize/forwarder"
require "metricize/client"
