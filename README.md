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

    # start server in its own Ruby process (eg using lib/tasks/metrics.rake)
    Metricize::Server.new(username: 'name@example.com', password: 'api_key').start

    # start appropriate client (eg from config/initializers/metrics.rb)
    if Rails.env == 'production'
      client_config = { prefix:     "app_name.#{Rails.env}",
                        queue_host: 'localhost',
                        queue_name: "app_name.#{Rails.env}.metrics_queue",
                        logger:     Rails.logger }

      METRICS = Metricize::Client.new(client_config)

    else
      METRICS = Metricize::NullClient
    end

    # use client interface to send metrics from the app
    METRICS.increment('content_post.make') # increment by default value of 1
    METRICS.increment('bucket.make', by: 5) # increment counter by 5
    METRICS.measure('worker_processes', 45) # send a snapshot of a current value (eg 45)
    METRICS.time('facebook.request_content') do  # record the execution time of a slow block
      # make API call...
    end
    METRICS.measure('stat', 45, source: 'my_source') # break out stat by subgrouping

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
