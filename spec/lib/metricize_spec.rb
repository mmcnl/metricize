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
    RestClient.should_receive(:post)
    metrics.measure('value_stat', 777)
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
    RestClient.should_receive(:post)
    metrics.measure('value_stat', 777)
    metrics.send!
  end

  it "sends all stats in a batch with the same timestamp" do
    RestClient.should_receive(:post).with(anything, /measure_time":1234}/, anything)
    metrics.measure('value1', 5)
    metrics.send!
  end

  it "adds subgrouping information if present" do
    expected_output = /"name":"host.counter1.count","value":1.*"source":"my_source"/
    RestClient.should_receive(:post).with(anything, expected_output, anything)
    metrics.increment('counter1', :source => 'my_source')
    metrics.send!
  end

  it "consolidates repeated counts into an aggregate total before sending" do
    RestClient.should_receive(:post).with(anything,
                                          /counter1.count","value":6.*aggregate/,
                                          anything)
    metrics.increment('counter1')
    metrics.increment('counter1', by: 5)
    metrics.send!
  end

  it "sends value stats when asked to measure something" do
    RestClient.should_receive(:post).with(anything,
                                          /value1","value":10.*value2","value":20/,
                                          anything)
    metrics.measure('value1', 10)
    metrics.measure('value2', 20)
    metrics.send!
  end

  it "raises an error when measure is called without a numeric value" do
    expect { metrics.measure('boom', {}) }.to raise_error(ArgumentError, /no numeric value provided in measure call/)
    expect { metrics.measure('boom', 'N') }.to raise_error(ArgumentError, /no numeric value provided in measure call/)
    metrics.send!
  end

  it "rounds values stats to 2 decimals" do
    RestClient.should_receive(:post).with(anything, /value1","value":3.33/, anything)
    metrics.measure('value1', 3.3333333)
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

    it "adds percentile stats for each value stat" do
      expected_output = /value_stat1.25e","value":5.0.*value_stat1.75e","value":15.0.*value_stat1.95e","value":19.0.*value_stat2.25e/
      RestClient.should_receive(:post).with(anything, expected_output, anything)
      (1..20).each { |value| metrics.measure('value_stat1', value) }
      metrics.measure('value_stat2', 7)
      metrics.send!
    end
  end

  it "times and reports the execution of a block of code in milliseconds" do
    RestClient.should_receive(:post).with(anything,
                                          /"name":"host.my_slow_code.time","value":5000/,
                                          anything)
    metrics.time('my_slow_code') do
      Timecop.travel(5) # simulate 5000 milliseconds of runtime
    end
    metrics.send!
  end

  it "retries sending if it encounters an error" do
    RestClient.stub(:post).and_raise(StandardError)
    metrics.increment('counter1')
    metrics.send!
    RestClient.should_receive(:post)
    metrics.send!
  end

end

