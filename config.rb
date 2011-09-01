require 'rubygems'
require 'bundler/setup'
require 'net/netrc'

rc = Net::Netrc.locate('youtube')

require './lib/youtube_lib'
SESSION = YoutubeLib::Session.new rc.login, rc.password, rc.account

LAG_TV = YoutubeLib::Author.new :name => 'LifesAGlitchTV', :session => SESSION
