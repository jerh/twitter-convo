require 'logger'
require 'active_record'
require 'twitter'

# Find conversations between A with follower count @popular and B with follower count @celebrity
# over a period of @time_range.
# A conversation is defined as when a user X mentions Y in a tweet x and Y replied to the tweet y
# (and mentions X in the tweet as well)

class ConvoFinder

  def initialize(opts)
    @start_time = Time.now # used to determine two weeks
    @last_twitter_call = Time.now # used to even request
    @popular = opts[:low_follower_count]
    @celebrity = opts[:high_follower_count]
    @time_range = opts[:num_weeks]*7*24*60*60
    @search_new = opts[:search_new]
    @seed = opts["seed"]
    # local map for a user's follower count (key => screen_name, value => followers_count)
    @user_cache = {}

    def setup(opts)
      # setup logging
      begin
        @logger = Logger.new(opts["log_file"])
      rescue
        raise "Please initialize your log file"
      end

      # setup active record
      ActiveRecord::Base.logger = @logger
      ActiveRecord::Base.establish_connection opts["db_config"]

      return if !@search_new

      ActiveRecord::Schema.define :version => 1 do
        drop_table   :users if ActiveRecord::Base.connection.table_exists? :users
        create_table :users do |t|
          t.string   :screen_name, :null => false
          t.integer  :followers_count, :default => 0
          t.timestamps
        end

        drop_table   :statuses if ActiveRecord::Base.connection.table_exists? :statuses 
        create_table :statuses do |t|
          t.integer  :user_id, :null => false
          t.string   :text, :null => false
          t.integer  :in_reply_to_status_id
          t.string   :in_reply_to_screen_name
          # prefix t to column names to indicate that these values are from twitter
          t.integer  :tid, :null => false
          t.datetime :tcreated_at, :null => false
        end

        drop_table   :mentions if ActiveRecord::Base.connection.table_exists? :mentions 
        create_table :mentions do |t|
          t.integer :status_id
          t.string  :screen_name, :null => false
        end
      end

    end

    def define_user_methods
      popular = @popular
      celebrity = @celebrity
      # define popularity methods
      User.send :define_method, :popular? do
        self.followers_count > popular
      end
      User.send :define_method, :celebrity? do
        self.followers_count > celebrity
      end
    end

    setup opts
    define_user_methods
  end

  def run
    get_users_data @seed if @search_new
    @seed.each { |u| get_user_tweets_data u } if  @search_new

    # From the user_mentions in tweets by users in seed, we have a list of screen_names we 
    # do not have user data for
    new_users = Mention.all.map(&:screen_name).uniq - @seed
    get_users_data new_users
    new_users.each { |u| get_user_tweets_to_users u }

    # Should have enough data to find convos
    @logger.info ("Finding all conversations")
    Status.get_conversations.each { |from,to| print_convo from, to }
  end

  private
  # get the tweets data from all users we have existing in the system
  def get_user_tweets_to_users(screen_name)
    @logger.info "Getting tweets from #{screen_name} to users that mentions him/her in a tweet"
    return if @user_cache[screen_name] < @popular

    user = User.where(:screen_name => screen_name).first

    # Get all users that tweeted to screen_name
    # SELECT DISTINCT users.screen_name
    # FROM "users" INNER JOIN "statuses" ON "statuses"."user_id"= "users"."id"
    #              INNER JOIN "mentions" ON "mentions"."status_id" = "statuses"."id"
    # WHERE "mentions"."screen_name" = '#{screen_name}'
    mentions = User.joins(:statuses => :mentions)
                   .where('mentions.screen_name' => screen_name)
                   .select('users.screen_name').uniq
    query = "from:#{screen_name} (@#{mentions.map(&:screen_name).join(' OR @')})"
    each_tweet_from_search(query) do |tweet|
      break if @start_time - Time.parse(tweet[:created_at]) > @time_range
      next if tweet[:in_reply_to_screen_name].nil? && tweet[:entities][:user_mentions].empty?
      user.save_tweet! tweet
    end
  end

  # Helper method to page through all results of the query
  def each_tweet_from_search(query)
    opts = {:rpp => 100, :include_entities => true}

    @logger.info "Querying twitter with query #{query} and params #{opts}"
    tweets = Twitter.search(query, opts)
    tweets.results.each { |r| yield r.attrs}
    while tweets.results.size == tweets.results_per_page && tweets.page < 15
      @logger.info "Querying twitter with query #{query}, params #{opts}, page #{tweets.page+1}"
      tweets = Twitter.search(query, opts.merge(:page => tweets.page+1))
      tweets.results.each { |r| yeild r.attrs }
    end
  end

  # Get user data (screen_name, followers_count) and store into db
  def get_users_data(users)
    users.page(100) do |page|
      @logger.info "Getting user data of #{users}"
      Twitter.users(page, :include_entities => true).each do |u|
        tuser = u.attrs
        user = User.new :screen_name => tuser[:screen_name]

        # If we can't read the user's tweet or user last updated more than 2 weeks ago so
        # we could leave the user's follower count as 0
        if tuser[:status] && @start_time - Time.parse(tuser[:status][:created_at]) < @time_range
          user.followers_count = tuser[:followers_count]
        end
        user.save!

        @user_cache[user.screen_name] = user.followers_count || 0
      end
    end
  end

  def get_user_tweets_data(screen_name)
    @logger.info "Getting tweet data of #{screen_name}"
    # return if the user's popularity level does not meet the requirement
    # or we do not have the user data (this might occur if a user's account is closed)
    return if @user_cache[screen_name].nil? || @user_cache[screen_name] < @popular

    count = 3
    begin
      throttle_twitter_calls
      @logger.info "Calling Twitter for tweets from #{screen_name}"
      tweets = Twitter.user_timeline(screen_name, :count => 200, :include_entities => true)
      @last = Time.now.to_f

      user = User.where(:screen_name => screen_name).first
      tweets.each do |t|
        tweet = t.attrs
        # break if the tweet is longer than we cared for
        break if @start_time - Time.parse(tweet[:created_at]) > @time_range

        # skip if the tweet wasn't address to anyone since it couldn't form a conversation
        if tweet[:in_reply_to_screen_name].nil? && tweet[:entities][:user_mentions].empty? 
          next
        end

        user.save_tweet! tweet
      end
    rescue Exception => e
      @last = Time.now.to_f
      @logger.error "Failed getting tweets for #{screen_name} due to #{e.inspect}"
      count -= 1
      retry if count > 0
    end
  end

  def throttle_twitter_calls
    if Twitter.rate_limit.reset_in
      rate_limit = Twitter.rate_limit
      sleep_time = (rate_limit.reset_in - Time.now.to_f + @last)/rate_limit.remaining
      sleep_time = 1 if sleep_time < 0
      @logger.info "Sleeping for #{sleep_time} to spread out twitter requests"
      sleep sleep_time
    end
  end

  def print_convo(from, to)
    seperator = ''.center(100, '-')
    puts seperator
    puts from
    puts to
    puts seperator
  end
end
