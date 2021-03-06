require 'cinch'

module Cinch
  module Plugins
    class MessageHistory
      include Cinch::Plugin

      listen_to :channel

      # Stores the last few messages each user has sent to the channel, as well
      # as a global list of messages. This is configured in lib/snap/bot.rb
      def listen(m)
        return if m.message.to_s =~ /^#{@bot.config.plugins.prefix}[a-zA-Z]/ # Don't sed a call to any commands
        return if m.user == @bot

        json = { :nick => m.user.nick, :message => m.message }.to_json

        @bot.redis.lpush "#{m.channel}:#{m.user.nick}:messages", json
        @bot.redis.lpush "#{m.channel}:messages", json

        if @bot.redis.llen("#{m.channel}:#{m.user.nick}:messages").to_i > (config[:user_messages] || 10)
          @bot.redis.rpop "#{m.channel}:#{m.user.nick}:messages"
        end

        if @bot.redis.llen("#{m.channel}:messages").to_i > (config[:channel_messages] || 25)
          @bot.redis.rpop "#{m.channel}:messages"
        end
      end
    end
  end
end
