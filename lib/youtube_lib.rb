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

    def inspect
      "#<#{self.class.name}:0x%08x @login=#{login.inspect} @source=#{source.inspect}>" % (object_id * 2)
    end
  end

  module ApiData
    def self.included klass
#NOTE: should :hash be avaliable externally?
      klass.send :attr_reader, :hash, :session
      klass.send :extend, ClassMethods
    end

    module ClassMethods
      def property name, args={}
        define_method args[:method_name] || name do
          val = hash[name]
          val = val.is_a?(Array) ? val[0] : val
          val = val.is_a?(Hash) ? val['content'] : val
          val = val.send(args[:post_meth]) if args.include? :post_meth
          val
        end
      end
    end
  end
  module Collection
    def self.included klass
      klass.send :include, Enumerable
    end

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
      #xml = File.read('videos')
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

    def new_subscription_videos
      @new_subscription_videos ||= begin
        xml = YoutubeLib.get "https://gdata.youtube.com/feeds/api/users/#{name}/newsubscriptionvideos", session
        #xml = File.read('newsubscriptionvideos')
        Videos.new :hash => XmlSimple.xml_in(xml),
                   :session => session
      end
    end
  end
  User = Author

  class Playlists
    include ApiData
    include Collection

    def initialize params={}
      @hash = params[:hash] if params.include? :hash
      @session = params[:session] if params.include? :session
    end

    def each &block
#TODO: make this iterate over all entries and continue with "next" feed
      hash['entry'].map do |hash|
        yield Playlist.new :hash => hash, :session => session
      end
    end
  end

  class Playlist
    include ApiData

    def initialize params={}
      @hash = params[:hash] if params.include? :hash
      @session = params[:session] if params.include? :session
    end

    property 'playlistId', :method_name => :id
    property 'published'
    property 'updated'
    def categories
#TODO: make this a Category
      hash['category'].map{|d| d['term'] }
    end
    property 'title'
    property 'content'
    def author
#TODO: make this an Author
      hash['author'][0]['name'][0]
    end
    property 'description'

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

    def each &block
#TODO: make this iterate over all entries and continue with "next" feed
      hash['entry'].map do |hash|
        yield Video.new :hash => hash, :session => session
      end
    end
  end

  class Video
    include ApiData

    def initialize params={}
      @hash = params[:hash] if params.include? :hash
      @session = params[:session] if params.include? :session
    end

    property 'id'
    property 'published'
    property 'updated'
    def categories
#TODO: make this a Category
      hash['category'].map{|d| d['term'] }
    end
    property 'title'
    property 'content'
    def author
#TODO: make this an Author
      hash['author'][0]['name'][0]
    end
#NOTE: when part of a playlist
    property 'position', :post_meth => :to_i

    def url
      hash['link'].detect{|l| l['rel'] == 'alternate' && l['type'] == 'text/html' }['href']
    end
  end

end
