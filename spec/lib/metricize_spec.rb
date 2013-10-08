require "spec_helper"

class TestError < StandardError; end

describe Metricize do
  let(:logger) { double.as_null_object }
  let(:forwarder) { Metricize::Forwarder.new( :password => 'api_key',
                                             :username => 'name@example.com',
                                             :logger   => logger) }

  let(:client) { Metricize::Client.new( :prefix => 'prefix', :logger => logger, :log_sampling_ratio => 1.0 ) }

  before do
    Timecop.freeze(Time.at(1234))
    RestClient.stub(:post)
  end

  after do
    Timecop.return
    forwarder.send(:clear_queue)
  end

  it "provides null object implementations to allow for easily disabling metrics functionality" do
    expect(Metricize::NullClient).to respond_to(:new, :increment, :measure, :time, :establish_redis_connection)
    expect(Metricize::NullForwarder).to respond_to(:new, :go!)
  end

  it "properly uses the remote API to send gauge stats" do
    client.increment('stat.name', :source => 'my_source')
    RestClient.should_receive(:post).with do | api_url, post_data, request_params |
      expect(api_url).to eq("https://name%40example.com:api_key@metrics-api.librato.com/v1/metrics")
      first_gauge = JSON.parse(post_data)['gauges'].first
      expect(first_gauge['name']).to eq "prefix.stat.name.count"
      expect(first_gauge['source']).to eq "my_source"
      expect(first_gauge['attributes']).to eq("source_aggregate" => true, "summarize_function" => "sum")
      expect(request_params).to eq( :timeout => 12, :content_type => "application/json" )
    end
    forwarder.go!
  end

  it "sends stats when requested with go!" do
    client.measure('value_stat', 777)
    RestClient.should_receive(:post)
    forwarder.go!
  end

  it "does not send stats if none have been recorded" do
    RestClient.should_not_receive(:post)
    forwarder.go!
  end

  it "clears sent items after a successful request and does not send to remote again if queue is empty" do
    client.increment('stat.name')
    forwarder.go!
    RestClient.should_not_receive(:post)
    forwarder.go!
  end

  it "limits the number of metrics forwarded to the remote in a single request" do
    forwarder.instance_variable_set(:@batch_size, 3)
    forwarder.instance_variable_set(:@remote_requests, 1)
    7.times { | n| client.increment('stat.name' + n.to_s) }
    forwarder.go!
    expect(forwarder.send(:queue_length)).to eq 4
    forwarder.go!
    expect(forwarder.send(:queue_length)).to eq 1
    forwarder.go!
    expect(forwarder.send(:queue_length)).to eq 0
  end
  it "removes special characters and spaces and converts the metric names and sources to dotted decimal snake_case" do
    client.increment(' My UNRULY stat!@#$%^&*\(\) ')
    RestClient.should_receive(:post).with(anything, /my_unruly_stat/, anything)
    forwarder.go!
    client.increment('test', :source => ' My UNRULY source!@#$%^&*\(\) ')
    RestClient.should_receive(:post).with(anything, /my_unruly_source/, anything)
    forwarder.go!
  end

  it "converts passed in objects to string before using them as metric or source names" do
    client.increment(Numeric, :source => Integer)
    RestClient.should_receive(:post).with do | _, post_data |
      expect(post_data).to match( /prefix.numeric.count/ )
      expect(post_data).to match( /source":"integer"/ )
    end
    forwarder.go!
  end

  it "sends all stats in a batch with the same timestamp" do
    client.measure('value1', 5)
    RestClient.should_receive(:post).with(anything, /measure_time":1234\D/, anything)
    forwarder.go!
  end

  it "adds subgrouping information if present" do
    client.increment('counter1', :source => 'my_source')
    RestClient.should_receive(:post).with(anything, /"source":"my_source"/, anything)
    forwarder.go!
  end

  it "consolidates repeated counts into an aggregate total before sending" do
    client.increment('counter1')
    client.increment('counter1', :by => 5)
    RestClient.should_receive(:post).with do | _, post_data |
      expect(post_data).to match( /"value":6/ )
      expect(post_data).to match( /"name":"prefix.counter1.count"/ )
      expect(post_data).to match( /source_aggregate":true/ )
      expect(post_data).to match( /summarize_function":"sum"/ )
    end
    forwarder.go!
  end

  it "aggregates requests from multiple clients" do
    client.increment('counter1')
    client2 = Metricize::Client.new( :prefix => 'prefix', :logger => logger )
    client2.increment('counter1', :by => 5)
    RestClient.should_receive(:post).with do | _, post_data |
      expect(post_data).to match( /"value":6/ )
      expect(post_data).to match( /"name":"prefix.counter1.count"/ )
    end
    forwarder.go!
  end

  it "sends value stats when asked to measure something" do
    client.measure('value1', 10)
    client.measure('value2', 20)
    RestClient.should_receive(:post).with do | _, post_data |
      gauges = JSON.parse(post_data)['gauges']
      expect(gauges[1]['name']).to eq "prefix.value1"
      expect(gauges[1]['value']).to eq 10.0
      expect(gauges[0]['name']).to eq "prefix.value2"
      expect(gauges[0]['value']).to eq 20.0
    end
    forwarder.go!
  end

  it "logs in splunk format a sampling of metrics" do
    client = Metricize::Client.new( :prefix => 'prefix', :logger => logger, :log_sampling_ratio => 0.10 )
    srand(1234)
    logger.should_receive(:info).with(/prefix_value1=10.0/m).exactly(9).times
    100.times { client.measure('value1', 10) }
    logger.should_receive(:info).with(/prefix_value2=20.0/m).exactly(6).times
    100.times { client.measure('value2', 20) }
  end

  it "raises an error when measure is called without a numeric value" do
    expect { client.measure('boom', {}) }.to raise_error(ArgumentError, /no numeric value provided in measure call/)
    expect { client.measure('boom', 'NaN') }.to raise_error(ArgumentError, /no numeric value provided in measure call/)
  end

  it "rounds value stats to 4 decimals" do
    client.measure('value1', 1.0/7.0)
    RestClient.should_receive(:post).with(anything, /value":0.1429/, anything)
    forwarder.go!
  end

  describe "adding aggregate stats based on all instances of each value stat in this time interval" do

    it "splits out aggregate stats for each subgrouping for values with multiple sources" do
      [4,5,6].each { |value| client.measure('value1', value, :source => 'source1') }
      [1,2,3].each { |value| client.measure('value1', value, :source => 'source2') }
      RestClient.should_receive(:post).with do | url, post_data |
        gauges = JSON.parse(post_data)['gauges']
        expect(gauges).to include("name"=>"prefix.value1.50e", "source"=> "source1", "value"=>5.0)
        expect(gauges).to include("name"=>"prefix.value1.50e", "source"=> "source2", "value"=>2.0)
      end
      forwarder.go!
    end

    it "adds the count of measurements to gauges" do
      [4,5,6].each { |value| client.measure('value1', value) }
      RestClient.should_receive(:post).with do | url, post_data |
        gauges = JSON.parse(post_data)['gauges']
        expect(gauges).to include("name"=>"prefix.value1.count", "value"=>3, "attributes"=>{"source_aggregate"=>true, "summarize_function"=>"sum"})
      end
      forwarder.go!
    end

    it "calculates standard deviation and mean" do
      values = [1,2,3,4,5,6].extend(Metricize::Stats)
      expect(values.mean).to eq(3.5)
      expect(values.standard_deviation).to be_within(0.01).of(1.87083)
    end

    it "adds percentile stats for each value stat" do
      (1..20).each { |value| client.measure('value_stat1', value) }
      client.measure('value_stat2', 7)
      RestClient.should_receive(:post).with do | _, post_data |
        gauges = JSON.parse(post_data)['gauges']
        expect(gauges).to include("name"=>"prefix.value_stat1.50e", "value"=>10.0)
        expect(gauges).to include("name"=>"prefix.value_stat1.95e", "value"=>19.0)
        expect(gauges).to include("name"=>"prefix.value_stat2.95e", "value"=>7.0)
      end
      forwarder.go!
    end

    it "logs a histogram for value stats with more than 5 measurements" do
      2.times { logger.should_receive(:info) }
      [10,10,15,15,15,19].each { |value| client.measure('value_stat1', value) }
      #3|          *
      #2| *        *
      #1| *        *     *
      #0+------------------
       # 10 11 13 14 16 17
      logger.should_receive(:info).with(/10 11 13 14 16 17/m)
      forwarder.go!
    end

    it "doesn't log a histogram for value stats with less than 5 measurements" do
      [10,10,15].each { |value| client.measure('value_stat1', value) }
      2.times { logger.should_receive(:info) }
      logger.should_not_receive(:info).with(/Histogram/)
      forwarder.go!
    end

    it "handles cases where all values are the same" do
      [10,10,10,10,10,10].each { |value| client.measure('value_stat1', value) }
      logger.should_not_receive(:error)
      forwarder.go!
    end

  end

  it "times and reports the execution of a block of code in milliseconds" do
    client.time('my_slow_code') do
      Timecop.travel(5) # simulate 5000 milliseconds of runtime
    end
    RestClient.should_receive(:post).with do | _, post_data |
      first_gauge = JSON.parse(post_data)['gauges'].first
      expect(first_gauge['name']).to eq('prefix.my_slow_code.time')
      expect(first_gauge['value']).to be_within(0.2).of(5000)
    end
    forwarder.go!
  end

  it "rescues and logs redis errors in client" do
    Redis.any_instance.stub(:lpush).and_raise(TestError)
    logger.should_receive(:error).with(/Client.*TestError/)
    client.increment('counter1')
  end

  it "rescues and logs redis errors in forwarder" do
    client.increment('counter1')
    Redis.any_instance.stub(:lrange).and_raise(TestError)
    logger.should_receive(:error).with(/Forwarder.*TestError/)
    forwarder.go!
  end

  it "rescues and logs errors when printing histograms" do
    10.times { client.measure('value1', 1.0) }
    AsciiCharts::Cartesian.any_instance.stub(:draw).and_raise(TestError)
    logger.should_receive(:error).with(/Forwarder.*TestError/)
    forwarder.go!
  end

end
