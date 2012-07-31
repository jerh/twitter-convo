require 'trollop'
require 'yaml'

Dir[File.dirname(__FILE__) + '/lib/*.rb'].each { |file| require file }

opts = Trollop::options do
  opt :config_file, "Configuration for the app in yaml format", :type => :string, :default => 'config/default.yaml'
  opt :low_follower_count, "Smaller follower number", :type => :int, :default => 125000
  opt :high_follower_count, "Larger follower number", :type => :int, :default => 1000000
  opt :num_weeks, "Number of weeks from today we are looking for conversation", :type => :int, :default => 2
  opt :search_new, "If true will drop existing database (if given) and look for new info online", :type => :boolean, :default => true
end

if File.exists? opts[:config_file]
  configs = YAML.load(open(opts[:config_file]))
else
  raise "Config file given does not exist"
end

opts.delete! :config_file
finder = ConvoFinder.new(opts.merge configs)
finder.run
