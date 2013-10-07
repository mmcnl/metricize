# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'metricize/version'

Gem::Specification.new do |spec|
  spec.name          = "metricize"
  spec.version       = Metricize::VERSION
  spec.authors       = ["Matt McNeil"]
  spec.email         = ["mmcneil@liveworld.com"]
  spec.description   = %q{Simple client/forwarder system to aggregate metrics and periodically send them to a stats service}
  spec.summary       = %q{Collect, aggregate, and send metrics to a stats service}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "timecop"
  spec.add_development_dependency "fakeredis"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "pry"

  spec.add_runtime_dependency "rest-client"
  spec.add_runtime_dependency "json"
  spec.add_runtime_dependency "redis"
  spec.add_runtime_dependency "ascii_charts"
  spec.add_runtime_dependency "pry"

end
