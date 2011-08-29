require 'net/http'
require 'xmlsimple'
require 'ruby-debug'
module YoutubeLib
  def self.get url, session
    uri = URI.parse(url)
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true
    response = https.get(uri.path, {
      'Content-Type' => 'application/x-www-form-urlencoded',
      'Authorization' => "GoogleLogin auth=#{session.auth}",
      'X-GData-Key' => "key=#{session.developer_key}"
    })
    raise response.message unless response.code == '200'
    response.body
  end

  class Session
    attr_reader :login, :password, :developer_key, :source
    def initialize login, password, key, source='YoutubeLib'
      @login, @password, @developer_key, @source = login, password, key, source
    end

    def auth
      @auth ||= begin
        uri = URI.parse("https://www.google.com/accounts/ClientLogin")
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
        data = "Email=#{URI.escape(login)}&Passwd=#{URI.escape(password)}&service=youtube&source=#{source}"
        headers = {
          'Content-Type' => 'application/x-www-form-urlencoded'
        }
        response = https.post(uri.path, data, headers)
        raise response.message unless response.code == '200'
        response.body[/Auth=(.*)/, 1]
      end
    end
  end

  module ApiData
    def self.included klass
#NOTE: should :hash be avaliable externally?
      klass.send :attr_reader, :hash, :session
    end
  end
  module Collection
    def count
      hash['totalResults'][0].to_i
    end
    alias_method :length, :count
    def title
      hash['title'][0]
    end
    def author
#TODO: make this an Author
      hash['author'][0]['name']
    end
  end

  class Author
    include ApiData

    attr_reader :name
    def initialize params={}
      @name = params[:name] if params.include? :name
      @session = params[:session] if params.include? :session
      @hash = params[:hash] if params.include? :hash
    end

    def uploads
      xml = YoutubeLib.get "https://gdata.youtube.com/feeds/api/users/#{name}/uploads", session
      #Videos.new :hash => XmlSimple.xml_in(File.read('videos')),
      #           :session => session
      Videos.new :hash => XmlSimple.xml_in(xml),
                 :session => session
    end

    def playlists
      @playlists ||= begin
        xml = YoutubeLib.get "https://gdata.youtube.com/feeds/api/users/#{name}/playlists?v=2", session
        Playlists.new :hash => XmlSimple.xml_in(xml),
                      :session => session
      end
    end
  end

  class Playlists
    include ApiData
    include Collection

    def initialize params={}
      @hash = params[:hash] if params.include? :hash
      @session = params[:session] if params.include? :session
    end

    def playlists
      @playlists ||= hash['entry'].map{|data| Playlist.new :hash => data, :session => session }
    end
  end

  class Playlist
    include ApiData

    def initialize params={}
      @hash = params[:hash] if params.include? :hash
      @session = params[:session] if params.include? :session
    end

    def id
      hash['playlistId'][0]
    end
    def published
      hash['published'][0]
    end
    def updated
      hash['updated'][0]
    end
    def categories
#TODO: make this a Category
      hash['category'].map{|d| d['term'] }
    end
    def title
      hash['title'][0]['content']
    end
    def content
      hash['content']['content']
    end
    def author
#TODO: make this an Author
      hash['author'][0]['name'][0]
    end
    def description
      hash['description'][0]
    end

    def videos
      @videos ||= begin
        xml = YoutubeLib.get hash['feedLink'][0]['href'].gsub(/http:/, 'https:')+'?v=2', session
        Videos.new :hash => XmlSimple.xml_in(xml),
                   :session => session
      end
    end
  end

  class Videos
    include Collection
    include ApiData

    def initialize params={}
      @hash = params[:hash] if params.include? :hash
      @session = params[:session] if params.include? :session
    end

    def videos
#TODO: make this iterate over all entries and continue with "next" feed
      @videos ||= hash['entry'].map{|data| Video.new :hash => data, :session => session }
    end
  end

  class Video
    include ApiData

    def initialize params={}
      @hash = params[:hash] if params.include? :hash
      @session = params[:session] if params.include? :session
    end

    def id
      hash['id'][0]
    end
    def published
      hash['published'][0]
    end
    def updated
      hash['updated'][0]
    end
    def categories
#TODO: make this a Category
      hash['category'].map{|d| d['term'] }
    end
    def title
      hash['title'][0]['content']
    end
    def content
      hash['content']['content']
    end
    def author
#TODO: make this an Author
      hash['author'][0]['name'][0]
    end
    def position
#NOTE: when part of a playlist
      hash['position'][0].to_i
    end
  end

end
