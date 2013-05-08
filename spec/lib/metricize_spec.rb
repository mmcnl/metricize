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

  it "provides a sensible default send interval" do
    metrics =  Metricize.new(password: 'api_key', username: 'name@example.com', prefix: 'host')
    expect(metrics.instance_variable_get("@send_interval")).to eq(60.0)
  end

  it "properly uses the remote API to send stats" do
    api_url= "https://name%40example.com:api_key@metrics-api.librato.com/v1/metrics"
    post_data= /{"counters":\[{"name":"host.stat.name","value":1,"measure_time":1234,"source":"my_source"}/
    request_params = {:timeout=>5,:content_type=>"application/json"}
    RestClient.should_receive(:post).with(api_url, post_data, request_params)
    metrics.increment('stat.name', :source => 'my_source')
    metrics.send!
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

  it "sends counter stats" do
    post_data = /"name":"host.counter1","value":1,.*"name":"host.counter2","value":5/
    RestClient.should_receive(:post).with(anything, post_data, anything)
    metrics.increment('counter1')
    metrics.increment('counter2', by: 5)
    metrics.send!
  end

  it "addes subgrouping information if present" do
    post_data = /"name":"host.counter1","value":1.*"source":"my_source"/
    RestClient.should_receive(:post).with(anything, post_data, anything)
    metrics.increment('counter1', :source => 'my_source')
    metrics.send!
  end

  it "consolidates repeated counts into an aggregate total before sending" do
    RestClient.should_receive(:post).with(anything,
                                          /counter1","value":6/,
                                          anything)
    metrics.increment('counter1')
    metrics.increment('counter1', by: 5)
    metrics.send!
  end

  it "sends value stats" do
    RestClient.should_receive(:post).with(anything,
                                          /"name":"host.value1","value":10.*value2","value":20/,
                                          anything)
    metrics.measure('value1', 10)
    metrics.measure('value2', 20)
    metrics.send!
  end

  it "rounds values stats to 2 decimals" do
    RestClient.should_receive(:post).with(anything,
                                          /"name":"host.value1","value":3.33,/,
                                          anything)
    metrics.measure('value1', 3.3333333)
    metrics.send!
  end

  it "adds a count for each group of value stats" do
    RestClient.should_receive(:post).with(anything,
                                          /"name":"host.value1.count","value":2,/,
                                          anything)
    metrics.measure('value1', 5)
    metrics.measure('value1', 7)
    metrics.send!
  end

  it "adds the max value for each group of value stats" do
    RestClient.should_receive(:post).with(anything, /"name":"host.value_stat1.max","value":5/, anything)
    (1..5).each { |value| metrics.measure('value_stat1', value) }
    metrics.send!
  end

  it "adds the min value for each group of value stats" do
    RestClient.should_receive(:post).with(anything, /"name":"host.value_stat1.min","value":1/, anything)
    (1..5).each { |value| metrics.measure('value_stat1', value) }
    metrics.send!
  end

  it "adds the median value for each group of value stats" do
    RestClient.should_receive(:post).with(anything, /"name":"host.value_stat1.median","value":3/, anything)
    (1..5).each { |value| metrics.measure('value_stat1', value) }
    metrics.send!
  end

  it "adds percentile stats to each group of value stats" do
    post_data = /value_stat1.95e","value":19.0.*value_stat1.90e","value":18.0.*value_stat2.95e","value":7.0,/
    RestClient.should_receive(:post).with(anything, post_data, anything)
    (1..20).each { |value| metrics.measure('value_stat1', value) }
    metrics.measure('value_stat2', 7)
    metrics.send!
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

