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
    data ||= uri.query
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
      http.get(data ? "#{uri.path}?#{data}" : uri.path, headers)
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
      klass.send :attr_reader, :session
      klass.send :extend, ClassMethods
    end

#NOTE: should :hash be avaliable externally?
    def hash
      @hash || {}
    end

    def properties= args
      args.each do |key, value|
        send "#{key}=", value
      end
    end

    def link(rel='self')
      hash['link'].detect{|l| l['rel'] == rel }
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
      def list name, list_url, klass
        define_method name do |refresh=false|
          ivar_name = "@#{name}".to_sym
          return instance_variable_get(ivar_name) if instance_variables.include?(ivar_name) && !refresh
          url = list_url.gsub(/:(\w+)/){ send($1) }
          value = if url.empty?
            nil
          else
            xml = YoutubeLib.get url, session
            #xml = File.read('videos')
            klass = YoutubeLib.const_get(klass) if klass.is_a? String
            klass.new(:hash => XmlSimple.xml_in(xml), :session => session)
          end
          instance_variable_set(ivar_name, value)
        end
      end
    end
  end
  module Collection
    def self.included klass
      klass.send :include, Enumerable
      klass.send :include, InstanceMethods
      klass.send :extend, ClassMethods
      klass.send :alias_method, :length, :count
      klass.send :list, :next_collection, ":next_collection_url", klass
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
      def each &block
        items = []
        (hash['entry'] || []).each do |entry_hash|
          iterates = self.class.iterates
          iterates = self.class.iterates(YoutubeLib.const_get(iterates)) if iterates.is_a? String
          item = iterates.new(:hash => entry_hash, :session => session)
          items.push(item)
          yield item
        end
        if next_collection
          next_collection.each do |item|
            items.push(item)
            yield item
          end
        end
        items
      end
    private
      def next_collection_url
        if link('next')
          link('next')['href'].gsub(/^http:/, 'https:')
        end
      end
    end
    module ClassMethods
      def iterates klass=nil
        @iterates = klass unless klass.nil?
        @iterates
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

    list :uploads, "https://gdata.youtube.com/feeds/api/users/:name/uploads", 'Videos'
    list :playlists, "https://gdata.youtube.com/feeds/api/users/:name/playlists?v=2", 'Playlists'
    list :new_subscription_videos, "https://gdata.youtube.com/feeds/api/users/:name/newsubscriptionvideos", 'Videos'
  end
  User = Author

  class Playlists
    include ApiData
    include Collection
    iterates 'Playlist'

    def initialize params={}
      @hash = params.delete(:hash) if params.include? :hash
      @session = params.delete(:session) if params.include? :session
      self.properties = params
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

    list :videos, ":videos_url", 'Videos'
  private
    def videos_url
      hash['feedLink'][0]['href'].gsub(/http:/, 'https:')+'?v=2'
    end
  end

  class Videos
    include ApiData
    include Collection
    iterates 'Video'

    def initialize params={}
      @hash = params.delete(:hash) if params.include? :hash
      @session = params.delete(:session) if params.include? :session
      self.properties = params
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
    property 'position', :post_meth => :to_i

    def web_url
      link('alternate')['href']
    end
  end

end
