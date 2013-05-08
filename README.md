# Metricize

Simple in-memory server to receive metrics, aggregate them, and send them to a stats service

## Installation

Add this line to your application's Gemfile:

    gem 'metricize'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install metricize

## Usage

    # start server (eg from config/initializers/metrics.rb)
    METRICS = Metricize.new(password: 'api_key',
                            username: 'name@example.com',
                            prefix:   'host')
    METRICS.start

    # use client interface to send metrics from the app
    METRICS.increment('content_post.make') # increment by default value of 1
    METRICS.increment('bucket.make', by: 5) # increment counter by 5
    METRICS.measure('worker_processes', 45) # send a snapshot of a current value (eg 45)
    METRICS.time('facebook.request_content') do  # record the execution time of a slow block
      # make API call...
    end
    METRICS.measure('stat', 45, source: 'walmart') # break out stat by subgrouping

  Command line examples:

    $ METRICS_ENABLED=1 METRICS_INTERVAL=10 bin/rails server # start with metrics enabled in development

  Using metrics from within a Rails console:

    $ METRICS_ENABLED=1 bin/rails console
    Loading development environment (Rails 4.0.0.beta1)
    irb(main):001:0> METRICS.increment('testing')
    irb(main):002:0> METRICS.send!

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
