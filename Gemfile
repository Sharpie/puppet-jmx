source 'https://rubygems.org'

puppetversion = ENV['PUPPET_VERSION']
puppetversion ||= '~> 4.7' # Default version

gem 'puppet', puppetversion

gem 'puppetlabs_spec_helper', '~> 2.1'
gem 'puppet-strings', '~>1.0'

eval_gemfile "#{__FILE__}.local" if File.exists? "#{__FILE__}.local"
