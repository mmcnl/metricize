module Metricize

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
