require "spec_helper"

describe Metricize do
  let(:metrics) { Metricize.new(password:      'api_key',
                                username:      'name@example.com',
                                prefix:        'host',
                                logger:        Logger.new("/dev/null"),
                                send_interval: 0.1) }
  before do
    Timecop.freeze(Time.at(1234))
    RestClient.stub(:post)
    metrics.start
  end

  after do
    metrics.stop
    Timecop.return
  end

  it "properly uses the remote API to send gauge stats" do
    api_url= "https://name%40example.com:api_key@metrics-api.librato.com/v1/metrics"
    expected_output= /gauges":\[{"name":"host.stat.name.count","value":1,"source":"my_source","attributes":{"source_aggregate":true/
    request_params = {:timeout=>5,:content_type=>"application/json"}
    RestClient.should_receive(:post).with(api_url, expected_output, request_params)
    metrics.increment('stat.name', :source => 'my_source')
    metrics.send!
  end

  it "raises an error if client methods are called when the server is not running" do
    metrics.stop
    expect { metrics.increment('boom') }.to raise_error(RuntimeError, /server not running/)
    expect { metrics.measure('boom', 1) }.to raise_error(RuntimeError, /server not running/)
  end

  it "sends after waiting for the send interval to elapse" do
    metrics.measure('value_stat', 777)
    RestClient.should_receive(:post)
    sleep 0.15
  end

  it "does not send stats if none have been recorded" do
    RestClient.should_not_receive(:post)
    metrics.send!
  end

  it "clears queue and does not send again after a successful request" do
    metrics.increment('stat.name')
    metrics.send!
    RestClient.should_not_receive(:post)
    metrics.send!
  end

  it "sends immediately if requested with send!" do
    metrics.measure('value_stat', 777)
    RestClient.should_receive(:post)
    metrics.send!
  end

  it "removes special characters and spaces and converts the metric names and sources to dotted decimal snake_case" do
    metrics.increment(' My UNRULY stat!@#$%^&*\(\) ')
    RestClient.should_receive(:post).with(anything, /my_unruly_stat/, anything)
    metrics.send!
    metrics.increment('test', :source => ' My UNRULY source!@#$%^&*\(\) ')
    RestClient.should_receive(:post).with(anything, /my_unruly_source/, anything)
    metrics.send!
  end

  it "converts passed in objects to string before using them as metric or source names" do
    metrics.increment(Numeric, :source => Integer)
    RestClient.should_receive(:post).with(anything, /host.numeric.count.*source":"integer"/, anything)
    metrics.send!
  end

  it "sends all stats in a batch with the same timestamp" do
    metrics.measure('value1', 5)
    RestClient.should_receive(:post).with(anything, /measure_time":1234}/, anything)
    metrics.send!
  end

  it "adds subgrouping information if present" do
    metrics.increment('counter1', :source => 'my_source')
    expected_output = /"name":"host.counter1.count","value":1.*"source":"my_source"/
    RestClient.should_receive(:post).with(anything, expected_output, anything)
    metrics.send!
  end

  it "consolidates repeated counts into an aggregate total before sending" do
    metrics.increment('counter1')
    metrics.increment('counter1', by: 5)
    RestClient.should_receive(:post).with(anything,
                                          /counter1.count","value":6.*aggregate/,
                                          anything)
    metrics.send!
  end

  it "sends value stats when asked to measure something" do
    metrics.measure('value1', 10)
    metrics.measure('value2', 20)
    RestClient.should_receive(:post).with(anything,
                                          /value1","value":10.*value2","value":20/,
                                          anything)
    metrics.send!
  end

  it "raises an error when measure is called without a numeric value" do
    expect { metrics.measure('boom', {}) }.to raise_error(ArgumentError, /no numeric value provided in measure call/)
    expect { metrics.measure('boom', 'N') }.to raise_error(ArgumentError, /no numeric value provided in measure call/)
  end

  it "rounds value stats to 4 decimals" do
    metrics.measure('value1', 1.0/7.0)
    RestClient.should_receive(:post).with(anything, /value1","value":0.1429\}/, anything)
    metrics.send!
  end

  describe "adding aggregate stats based on all instances of each value stat in this time interval" do

    it "splits out aggregate stats for each subgrouping for values with multiple sources" do
      [4,5,6].each { |value| metrics.measure('value1', value, :source => 'source1') }
      [1,2,3].each { |value| metrics.measure('value1', value, :source => 'source2') }
      expected_output = /value1.50e","value":5.0,"source":"source1.*value1.50e","value":2.0,"source":"source2/
      RestClient.should_receive(:post).with(anything, expected_output, anything)
      metrics.send!
    end

    it "asks for server aggregation on the count of value stats" do
      metrics.measure('value_stat1', 7)
      expected_output = /value_stat1.count","value":1,"attributes":{"source_aggregate":true}/
      RestClient.should_receive(:post).with(anything, expected_output, anything)
      metrics.send!
    end
    it "adds percentile stats for each value stat" do
      (1..20).each { |value| metrics.measure('value_stat1', value) }
      metrics.measure('value_stat2', 7)
      expected_output = /value_stat1.25e","value":5.0.*value_stat1.75e","value":15.0.*value_stat1.95e","value":19.0.*value_stat2.25e/
      RestClient.should_receive(:post).with(anything, expected_output, anything)
      metrics.send!
    end
  end

  it "times and reports the execution of a block of code in milliseconds" do
    metrics.time('my_slow_code') do
      Timecop.travel(5) # simulate 5000 milliseconds of runtime
    end
    RestClient.should_receive(:post).with(anything,
                                          /"name":"host.my_slow_code.time","value":5000/,
                                          anything)
    metrics.send!
  end

  it "retries sending if it encounters an error" do
    metrics.increment('counter1')
    RestClient.stub(:post).and_raise(StandardError)
    metrics.send!
    RestClient.should_receive(:post)
    metrics.send!
  end

end

