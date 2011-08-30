require 'net/http'
require 'xmlsimple'
require 'ruby-debug'
module YoutubeLib
private
  def self.request method, url, data, session=nil
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    headers = {
      'Content-Type' => 'application/x-www-form-urlencoded'
    }
    data = data.map{|k,v| "#{k}=#{URI.escape(v)}"}.join('&') if data.is_a? Hash
    if session
      headers['Authorization'] = "GoogleLogin auth=#{session.auth}"
      headers['X-GData-Key'] = "key=#{session.developer_key}"
    end
    response = case method
    when :post
      http.post(uri.path, data, headers)
    when :delete
      http.delete(uri.path, headers)
    else
      http.get(uri.path, headers)
    end
    raise [response.code, response.message].join(': ') unless response.code == '200'
    response.body
  end
public
  def self.get url, session
    request :get, url, nil, session
  end
  def self.post url, data, session=nil
    request :post, url, data, session
  end
  def self.delete url, session=nil
    request :delete, url, nil, session
  end

  class Session
    attr_reader :login, :password, :developer_key, :source
    def initialize login, password, key, source='YoutubeLib'
      @login, @password, @developer_key, @source = login, password, key, source
    end

    def auth
      @auth ||= begin
        YoutubeLib.post("https://www.google.com/accounts/ClientLogin", {
          'Email' => login, 'Passwd' => password,
          'service' => 'youtube', 'source' => source
        })[/Auth=(.*)/, 1]
      end
    end

    def inspect
      "#<#{self.class.name}:0x%08x @login=#{login.inspect} @source=#{source.inspect}>" % (object_id * 2)
    end
  end

  module ApiData
    def self.included klass
#NOTE: should :hash be avaliable externally?
      klass.send :attr_reader, :session
      klass.send :extend, ClassMethods
    end

    def hash
      @hash || {}
    end

    def properties= args
      args.each do |key, value|
        send "#{key}=", value
      end
    end

    module ClassMethods
      def property name, args={}
        define_method args[:method_name] || name do
          val = instance_variable_get("@#{args[:method_name]}") || instance_variable_get("@#{name}")
          return val unless val.nil?
          val = hash[name]
          val = val.is_a?(Array) ? val[0] : val
          val = val.is_a?(Hash) ? val['content'] : val
          val = val.send(args[:post_meth]) if args.include? :post_meth
          val
        end

        define_method "#{args[:method_name]}=" do |val|
          instance_variable_set "@#{args[:method_name]}", val
        end
        define_method "#{name}=" do |val|
          instance_variable_set "@#{args[:method_name]}", val
        end
      end
    end
  end
  module Collection
    def self.included klass
      klass.send :include, Enumerable
      klass.send :include, InstanceMethods
      klass.send :alias_method, :length, :count
    end

    module InstanceMethods
      def count
        hash['totalResults'][0].to_i
      end
      def title
        hash['title'][0]
      end
      def author
#TODO: make this an Author
        hash['author'][0]['name']
      end
    end
  end

  class Author
    include ApiData

    property 'name'
    def initialize params={}
      @hash = params.delete(:hash) if params.include? :hash
      @session = params.delete(:session) if params.include? :session
      self.properties = params
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
      @hash = params.delete(:hash) if params.include? :hash
      @session = params.delete(:session) if params.include? :session
      self.properties = params
    end

    def each &block
#TODO: make this iterate over all entries and continue with "next" feed
      (hash['entry'] || []).map do |hash|
        yield Playlist.new :hash => hash, :session => session
      end
    end
  end

  class Playlist
    include ApiData

    def initialize params={}
      @hash = params.delete(:hash) if params.include? :hash
      @session = params.delete(:session) if params.include? :session
      self.properties = params
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
      @hash = params.delete(:hash) if params.include? :hash
      @session = params.delete(:session) if params.include? :session
      self.properties = params
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
      @hash = params.delete(:hash) if params.include? :hash
      @session = params.delete(:session) if params.include? :session
      self.properties = params
    end

    def id
      hash['id'][0][/[a-z0-9_-]{11}/i]
    end
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

    def web_url
      #hash['link'].detect{|l| l['rel'] == 'alternate' && l['type'] == 'text/html' }['href']
      link('alternate')['href']
    end
    def link(rel='self')
      hash['link'].detect{|l| l['rel'] == rel }
    end
  end

end
