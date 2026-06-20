# frozen_string_literal: true

module SlosiloCache
  class ClearCacheListener
    def initialize(db:, logger:, on_clear:)
      @db = db
      @logger = logger
      @on_clear = on_clear
      @listener_thread = nil
    end

    def start!
      return if @listener_thread&.alive?

      unless @db
        @logger.warn('SlosiloCache listener not started: no DB connection')
        return
      end

      @listener_thread = Thread.new do
        Thread.current.name = 'slosilo_cache_clear_listener' if Thread.current.respond_to?(:name=)
        @logger.debug("Thread #{Thread.current.object_id} is dtarting Slosilo cache clear listener on channel: clear_slosilo_cache")

        loop do
          @db.listen('clear_slosilo_cache') do |channel, payload|
            @logger.debug("Slosilo_cache_clear listener - received NOTIFY on #{channel} with payload: #{payload.inspect}")
            begin
              @on_clear.call
              @logger.debug('Slosilo cache cleared in response to NOTIFY')
            rescue => e
              @logger.error("Failed to clear Slosilo cache on NOTIFY: #{e.class}: #{e.message}")
            end
          end
        rescue => e
          @logger.error("Slosilo_cache_clear listener error (will try restart): #{e.class}: #{e.message}")
          next
        end
      end

      @listener_thread.abort_on_exception = true
    end
  end
end
