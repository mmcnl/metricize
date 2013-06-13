require "metricize/version"

require 'thread'
require 'rest-client'
require 'json'
require 'logger'
require 'redis'

module Metricize

  module SharedMethods
    def establish_logger(options)
      @logger            = options[:logger]            || Logger.new(STDOUT)
      @default_log_level = options[:default_log_level] || 'debug'
    end

    def establish_redis_connection(options)
      @queue_host  = options[:queue_host] || '127.0.0.1'
      @queue_port  = options[:queue_port] || 6379
      @queue_name  = options[:queue_name] || 'metricize_queue'

      log_message "connecting to Redis at #{@queue_host}:#{@queue_port}:#{@queue_name}", :info
      # don't use Redis.new to avoid issues when reconnecting (eg during Unicorn prefork reset)
      #  see http://stackoverflow.com/questions/10922197/resque-is-not-picking-up-redis-configuration-settings
      @redis = Redis.connect(:host => @queue_host, :port => @queue_port)

      log_message "queue_name=#{@queue_name}, queue_length=#{@redis.llen(@queue_name)}"
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
  end

  class NullServer
    def self.start; end
    def self.send!; end
  end

end

require "metricize/server"
require "metricize/client"
