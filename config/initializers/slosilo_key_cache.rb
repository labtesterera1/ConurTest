# frozen_string_literal: true

require 'slosilo'

require Rails.root.join('lib/slosilo_cache/cache_adapter')
require Rails.root.join('lib/slosilo_cache/cache_config')
require Rails.root.join('lib/slosilo_cache/cache')
require Rails.root.join('lib/slosilo_cache/countdown_timer')

logger = Rails.logger
# logger = Logger.new($stdout)

cache = SlosiloCache::Cache.new(
  db: Sequel::Model.db,
  timer: SlosiloCache::CountdownTimer.new(2), # 2 seconds
  logger: logger
)

SlosiloCache::CacheConfig.configure(
  feature_flags: Rails.configuration.feature_flags,
  adapter: Slosilo.adapter,
  cache: cache,
  logger: logger
)
