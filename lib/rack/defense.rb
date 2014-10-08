require 'rack'
require 'redis'

class Rack::Defense
  autoload :ThrottleCounter, 'rack/defense/throttle_counter'

  class Config
    attr_accessor :banned_response
    attr_accessor :throttled_response

    def throttle(name, max_requests, period, &block)
      counter = ThrottleCounter.new(name, max_requests, period)
      throttles[name] = lambda do |req|
        key = block[req]
        key && counter.throttle?(key)
      end
    end

    def ban(name, &block)
      bans[name] = block
    end

    def store=(value)
      @store = value.is_a?(String) ? Redis.new(url: value) : value
    end

    def store
      # Redis.new uses REDIS_URL environment variable by default as URL.
      # See https://github.com/redis/redis-rb
      @store ||= Redis.new
    end

    @throttles = {}
    @bans = {}
    @banned_response = ->(env) { [403, {'Content-Type' => 'text/plain'}, ["Forbidden\n"]] }
    @throttled_response = ->(env) { [429, {'Content-Type' => 'text/plain'}, ["Retry later\n"]] }
  end

  class << self
    def setup(&block)
      config = Config.new
      yield config
    end

    def banned?(req)
      config.bans.any? { |name, filter| filter.call(req) }
    end

    def throttled?(req)
      config.throtlles.any? { |name, filter| filter.call(req) }
    end

    private

    attr_accessor :config
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    klass = self.class
    req = ::Rack::Request.new(env)
    return klass.config.banned_response.call(env) if klass.banned?(req)
    return klass.config.throttled_response.call(env) if klass.throttled?(req)
    @app.call(env)
  end
end

