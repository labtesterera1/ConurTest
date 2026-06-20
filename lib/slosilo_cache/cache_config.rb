# frozen_string_literal: true

require 'slosilo'

module SlosiloCache
  module CacheConfig
    # Configures Slosilo adapter based on feature flag.
    def self.configure(feature_flags:, adapter:, cache:, logger:)
      if feature_flags.enabled?(:slosilo_key_cache)
        Slosilo.adapter = SlosiloCache::CacheAdapter.new(adapter, cache, logger)
        logger.info('Slosilo encryption key will be cached')
        true
      else
        logger.info('Slosilo encryption key cache is disabled')
        false
      end
    end
  end
end
