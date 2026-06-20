# frozen_string_literal: true

require_relative 'cache'

module SlosiloCache
  # In-memory caching decorator for Slosilo adapter.
  class CacheAdapter < Slosilo::Adapters::AbstractAdapter
    def initialize(wrapped_adapter, cache, logger)
      super()
      @wrapped_adapter = wrapped_adapter
      @cache = cache
      @logger = logger
    end

    def get_key(id)
      @logger.debug("SlosiloCacheAdapter.get_key - getting key for id: #{id}")
      key = @cache.get(id)

      @logger.debug("SlosiloCacheAdapter.get_key - SLOSILO_CACHE_HIT for id: #{id}") if key
      return key if key

      @logger.debug("SlosiloCacheAdapter.get_key - SLOSILO_CACHE_MISS for id: #{id}")

      key = @wrapped_adapter.get_key(id)
      return nil unless key

      @cache.put(id, key)
      key
    end

    def get_by_fingerprint(fingerprint)
      @logger.debug("SlosiloCacheAdapter.get_by_fingerprint - getting key for fingerprint: [redacted]")
      pair = @cache.get_by_fingerprint(fingerprint)

      @logger.debug("SlosiloCacheAdapter.get_by_fingerprint - SLOSILO_CACHE_HIT for fingerprint: [redacted]") if pair
      return pair if pair

      @logger.debug("SlosiloCacheAdapter.get_by_fingerprint - SLOSILO_CACHE_MISS for fingerprint: [redacted]")
      pair = @wrapped_adapter.get_by_fingerprint(fingerprint)
      return nil unless pair

      key, id = pair
      @cache.put(id, key)
      [key, id]
    end

    def put_key(id, key)
      @logger.debug("SlosiloCacheAdapter.put_key - put key for id: #{id}")
      @wrapped_adapter.put_key(id, key)
      @cache.put(id, key)
    end

    def each
      @wrapped_adapter.each do |id, key|
        @cache.put(id, key)
        yield(id, key)
      end
    end

    def clear_cache!
      @logger.debug("SlosiloCacheAdapter.clear_cache!")
      @cache.clear!
    end

    def method_missing(name, *args, &blk)
      @logger.debug("SlosiloCacheAdapter.method_missing - called for: #{name}")
      if @wrapped_adapter.respond_to?(name)
        @wrapped_adapter.public_send(name, *args, &blk)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      @wrapped_adapter.respond_to?(name, include_private) || super
    end
  end
end
