require 'cinch'
require_relative 'utils/highscores'
require_relative 'utils/suggestions'
require_relative 'utils/unsuggestions'
require_relative 'utils/misc'
require_relative 'wordgames/game'
require_relative 'wordgames/dict_word'
require_relative 'wordgames/response'


module Cinch::Plugins
  class WordGame
    Prefix_str = "w"
    Lock_str = "#{Prefix_str} lock"
    Unlock_str = "#{Prefix_str} unlock"
    Start_str = "#{Prefix_str} start"
    Guess_str = "guess"
    Cheat_str = "#{Prefix_str} cheat"
    Dict_str = "#{Prefix_str} dict"
    # Used in Highscore sub-module
    Highscores_str = "#{Prefix_str} scoreboard"
    # Used in Suggestions sub-module
    Suggest_str = "#{Prefix_str} suggest"
    # Used in Unsuggestions sub-module
    Unsuggest_str = "#{Prefix_str} unsuggest"

    include Cinch::Plugin

    set :help, <<-HELP
#{Start_str}
  Start a new game, with the bot picking a word
#{Guess_str} <word>
  Guess a word
#{Cheat_str}
  If you simply can't carry on, use this to find out the word (and end the game)
#{Dict_str} <dict>
  Specify a dictionary. Run with no parameters to see available dictionaries.
    HELP

    include Utils::HighScores
    include Utils::Suggestions
    include Utils::Unsuggestions

    def dict_filename(dict)
      dict ? config[:dicts][dict]['filename'] : "/usr/share/dict/words"
    end

    def initialize(*args)
      super

      @dict = Dictionary.from_file(dict_filename(config[:default_dict]))
      @ref_dict = Dictionary.from_file(dict_filename(config[:ref_dict]))
      @locked = false
      @game = nil
    end

    hook :pre, method: :locked
    def locked(m)
      s = m.message[1..-1]  # remove prefix
      s == Lock_str || s == Unlock_str ? true : !@locked
    end

    def response(m)
      Response.new(m, @game)
    end

    def headline(s)
      response = ""
      response << "┌─ " << s << " ─── " << "\n"
      response
    end

    def footer
      response = ""
      response << "\n" << "└ ─ ─ ─ ─ ─ ─ ─ ─\n"
      response
    end

    match(/#{Dict_str}\s*(\S*)/, method: :dict)
    def dict(m, dict)
      response = ""
      dicts = config[:dicts]
      if dict.empty?
        # print out available dicts
        response << headline("Available Dictionaries")
        dicts.each do |d, filename_desc|
          puts filename_desc
          if filename_desc['filename'] == @dict.filename
            d_str = Cinch::Formatting.format(:bold, d)
          else
            d_str = d
          end
          response << "#{d_str} - " << filename_desc['desc'] << "\n"
        end
        response << footer
      else
        valid = false
        # is this dict valid?
        dicts.each do |d, filename_desc|
          if d == dict
            valid = true
            @dict = Dictionary.from_file(filename_desc['filename'])
            response << "Dict \"#{d}\" selected!"
          end
        end
        response << "There is no such dict!" if !valid
      end
      m.reply(response)
    end


    match(/#{Lock_str}/, method: :lock)
    def lock(m)
      return if !@bot.admin?(m.user) || @locked
      @locked = true
      m.reply("Don't send me 500 emails! Game locked!")
    end

    match(/#{Unlock_str}/, method: :unlock)
    def unlock(m)
      return if !@bot.admin?(m.user) || !@locked
      @locked = false
      m.reply "Let the games continue!!"
    end

    match(/#{Start_str}/, method: :start)
    def start(m)
      if @game
        m.reply "There's already a game running!"
      else
        @game = Game.new(@dict, @ref_dict)
        response(m).start_game @bot.config.plugins.prefix
      end
    end

    match(/#{Cheat_str}/, method: :cheat)
    def cheat(m)
      if @game
        response(m).cheat
        @game = nil
        # inc_highscore(m.user)
      else
        response(m).game_not_started @bot.config.plugins.prefix
      end
    end

    match(/#{Guess_str} (\S+)/, method: :guess)
    def guess(m, word)
      if @game
        word = word.downcase
        if @game.guess(word, response(m))
          @game = nil
          # highlevel inc_score incoming!!!
          user = m.user.authed? ? m.user.authname : m.user

          self.highscores.inc_highscore(user)
          if config[:show_leaderboard_after_win]
            sleep 2
            self.highscores.print_highscores(m, 10)
          end
        else
          autocheat(m) if @game.number_of_guesses >= (config[:max_guesses] || 100)
        end
      else
        response(m).game_not_started @bot.config.plugins.prefix
      end
    end

    def autocheat(m)
      if @game
        response(m).autocheat
        @game = nil
      else
        response(m).game_not_started @bot.config.plugins.prefix
      end
    end


    class Game < WordGames::Game
      attr_reader :lower_bound, :upper_bound

      Blank_str = "__"

      def initialize(*args)
        super
        @lower_bound = Blank_str
        @upper_bound = Blank_str
      end

    protected
      def blank?(bound)
        bound == Blank_str
      end

      def guess_correct?(word, response)
        if @word == word
          response.game_won
          true
        else
          if @word.before?(word)
            @upper_bound = word if blank?(@upper_bound) || word < @upper_bound
          else
            @lower_bound = word if blank?(@lower_bound) || word > @lower_bound
          end
          response.wrong_word(@word.before_or_after(word))
          false
        end
      end
    end
  end
end
