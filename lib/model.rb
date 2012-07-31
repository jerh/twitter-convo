require 'active_record'

class User < ActiveRecord::Base
  has_many :statuses

  validates_presence_of :screen_name, :uniqueness => true
  validates :followers_count, :numericality => { :greater_than_or_equal_to => 0 }

  def save_tweet!(tweet)
    status = self.statuses.create :text => tweet[:text],
                                  :in_reply_to_status_id => tweet[:in_reply_to_status_id],
                                  :in_reply_to_screen_name => tweet[:in_reply_to_screen_name],
                                  :tid => tweet[:id],
                                  :tcreated_at => Time.parse(tweet[:created_at])
    tweet[:entities][:user_mentions].each { |m| status.mentions.create :screen_name => m[:screen_name] } 
  end
end

class Status < ActiveRecord::Base
  belongs_to :user
  has_many :mentions

  validates_presence_of :user_id, :text, :tcreated_at
  validates_presence_of :tid, :uniqueness => true

  # For status, get all it's mentions and check if any of the mentions replied
  # back. Query will look something like below
  # SELECT statuses.* FROM statuses
  # WHERE statuses.in_reply_to_user_id = <status_tid>
  # AND statuses.user_id IN
  # (SELECT users.user_id FROM users WHERE users.screen_name IN
  #  (SELECT mentions.screen_name FROM mentions WHERE mentions.status_id = <status_id>))
  def get_replies_to_conversation
    screen_name_of_mentions = self.mentions.map(&:screen_name)
    mentions_as_users = User.where("screen_name IN (?)", self.mentions.map(&:screen_name)) 
    Status.where("in_reply_to_status_id = ? AND user_id IN (?)",
                 self.tid, mentions_as_users.map(&:id))
  end

  def to_convo(type)
    [type,
     self.user.screen_name,
     "[#{self.user.followers_count}]",
     ":",
     self.text,
     self.tcreated_at].join(' ')
  end

  def self.get_conversations
    from_to = []
    self.all.each do |status|
      replies = status.get_replies_to_conversation
      if status.user.popular?
        replies.select! { |r| r.user.celebrity? }
      else
        replies.select! { |r| r.user.popular? }
      end
      replies.each do |r|
        from_to << [status.to_convo("FROM"), r.to_convo("TO")]
      end
    end
    from_to
  end

end

class Mention < ActiveRecord::Base
  belongs_to :status

  validates_presence_of :status_id, :screen_name
end
