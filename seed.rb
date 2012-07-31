# Get the users with more than 1 million followers from twitaholic.com

require 'open-uri'
require 'nokogiri'

def get_top_users(number)
  users = [] # store an array of hash with user
  page = Nokogiri::HTML(open("http://www.twitaholic.com/top#{number}/followers"))
  page.xpath("//div[@id='therest']/table/tbody/tr[position()>1]").each do |node|
    name = node.xpath("td[@class='statcol_name']/a[1]").attr('href').text.gsub(/\//,'')
    users << name
  end
  users
end

twitter_users = []
(100..500).step(100).each { |n| twitter_users.concat get_top_users(n) }
f = open('twitter-users.txt', 'w')
f.write(twitter_users.join("\n"))
f.close
