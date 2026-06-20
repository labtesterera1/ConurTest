# frozen_string_literal: true

require 'concurrent/map'
require_relative 'clear_cache_listener'

module SlosiloCache
  class Cache
    def initialize(db:, timer:, logger:, listener: nil)
      @db = db
      @timer = timer
      @logger = logger

      @listener = listener || SlosiloCache::ClearCacheListener.new(
        db: @db,
        logger: @logger,
        on_clear: method(:clear!)
      )

      @committed = Concurrent::Map.new        # id => key
      @tx_by_thread = Concurrent::Map.new     # thread_id => (id => key)
      @hooks_registered = Concurrent::Map.new # thread_id => true
    end

    # Get cached value by id. Returns nil on miss.
    # Handles time invalidation and transactional lookup.
    def get(id)
      invalidate_if_time_passed!
      @logger.debug("SlosiloCache.get - get for id: #{id}")
      if in_transaction?
        tx = tx_cache_for_current_thread
        v = tx[id]
        @logger.debug("SlosiloCache.get - TX_CACHE_HIT for id: #{id}") if v
        @logger.debug("SlosiloCache.get - TX_CACHE_MISS for id: #{id}") if v.nil?
        return v unless v.nil?
      end
      v = @committed[id]
      @logger.debug("SlosiloCache.get - COMMITTED_CACHE_HIT for id: #{id}") if v
      @logger.debug("SlosiloCache.get - COMMITTED_CACHE_MISS for id: #{id}") if v.nil?
      v
    end

    # Lookup by fingerprint in cache. Returns [key, id] or nil.
    # Scans committed and current thread transactional cache.
    def get_by_fingerprint(fingerprint)
      invalidate_if_time_passed!
      @logger.debug("SlosiloCache.get_by_fingerprint - looking up fingerprint")

      # Check transactional cache for current thread first if in tx
      if in_transaction?
        tx = tx_cache_for_current_thread
        tx.each_pair do |id, key|
          if key.respond_to?(:fingerprint) && key.fingerprint == fingerprint
            @logger.debug("SlosiloCache.get_by_fingerprint - TX_CACHE_HIT for fingerprint, id: #{id}")
            return [key, id]
          end
        end
      end

      # Check committed cache
      @committed.each_pair do |id, key|
        if key.respond_to?(:fingerprint) && key.fingerprint == fingerprint
          @logger.debug("SlosiloCache.get_by_fingerprint - COMMITTED_CACHE_HIT for fingerprint, id: #{id}")
          return [key, id]
        end
      end

      @logger.debug("SlosiloCache.get_by_fingerprint - CACHE_MISS for fingerprint")
      nil
    end

    # Put value into cache. If in transaction, store in the per-thread cache and
    # register commit/rollback hooks. Otherwise store in committed cache.
    def put(id, key)
      @listener.start!

      if in_transaction?
        ensure_hooks_registered!
        @logger.debug("SlosiloCache.put - in transaction, put key in TX_CACHE for id: #{id} and thread #{current_thread_id}")
        tx_cache_for_current_thread[id] = key
      else
        @logger.debug("SlosiloCache.put - put key in COMMITTED_CACHE for id: #{id}")
        @committed[id] = key
      end
      key
    end

    def clear!
      @logger.debug("SlosiloCache.clear - clear COMMITTED_CACHE from #{@committed.keys}")
      @committed.clear

      labels = @tx_by_thread.each_pair.flat_map do |thread_key, inner_map|
        inner_map.keys.map { |key_inner| "#{thread_key} - #{key_inner}" }
      end
 
      @logger.debug("SlosiloCache.clear - clear TX_CACHE for all threads: #{labels}")
      @tx_by_thread.clear

      @timer.reset

      # Clearing hooks in the middle of transaction can result
      # in registration of hooks multiple times (not bad but wasteful)
      # @hooks_registered.clear
    end

    private

    def invalidate_if_time_passed!
      return unless @timer&.passed?

      @logger.debug("SlosiloCache.invalidate_if_time_passed! - time passed, cleaning committed cache from #{@committed.keys}")

      # We are not clearing hooks and threads because if reset timer
      # passes in the middle of transaction the cached progress will
      # be lost and later nothing will get promoted to main cache.
      @committed.clear

      @timer.reset
    end

    def in_transaction?
      @db&.in_transaction?
    end

    def current_thread_id
      Thread.current.object_id
    end

    def tx_cache_for_current_thread
      tid = current_thread_id
      @tx_by_thread.compute_if_absent(tid) { Concurrent::Map.new }
    end

    def ensure_hooks_registered!
      return unless in_transaction?

      tid = current_thread_id
      return if @hooks_registered.put_if_absent(tid, true)

      @logger.debug("SlosiloCache.ensure_hooks_registered - register hooks for thread: #{tid}")

      # On commit: promote transactional entries into committed cache
      @db.after_commit do
        @logger.debug("SlosiloCache - after_commit hook fired in thread: #{tid}")
        if (tx = @tx_by_thread[tid])
          tx.each_pair { |id, key| @committed.compute(id) {|_| key } }
          @logger.debug("SlosiloCache - after_commit: move keys to COMMITTED_CACHE: #{tx.keys}")
          @tx_by_thread.delete(tid)
        end
        @hooks_registered.delete(tid)
      end

      # On rollback: drop transactional entries
      @db.after_rollback do
        @logger.debug("SlosiloCache - after_rollback hook fired in thread: #{tid}")
        @logger.debug("SlosiloCache - after_rollback: delete keys from TX_CACHE: #{@tx_by_thread[tid]&.keys || '[]'}")
        @tx_by_thread.delete(tid)
        @hooks_registered.delete(tid)
      end
    end
  end
end
