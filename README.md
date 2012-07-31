Twitter Convo
=============
Finds and prints on stdout conversation between two twitter users given a list of users.

Run
---
Run using the command `ruby twitter_convo.rb`
The following options is below:
`
          --config-file, -c <s>:   Configuration for the app in yaml format (default: config/default.yaml)
   --low-follower-count, -l <i>:   Smaller follower number (default: 125000)
  --high-follower-count, -h <i>:   Larger follower number (default: 1000000)
            --num-weeks, -n <i>:   Number of weeks from today we are looking for conversation (default: 2)
               --search-new, -s:   If true will drop existing database (if given) and look for new info online 
                                   (default: true)
                     --help, -e:   Show this message
`

Seed
----
`ruby seed.rb` generates a list of 500 "seed" users to start looking for conversations.

Errors
------
This program may fail due to Twitter errors or failed http calls.

Ruby Versions
-------------
This has been tested using Ruby-1.9.3 with activerecord-3.2.
