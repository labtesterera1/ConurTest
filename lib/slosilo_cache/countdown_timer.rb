# frozen_string_literal: true

module SlosiloCache
  class CountdownTimer
    def initialize(
      seconds = nil,
      now_proc = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    )
      @duration = normalize_duration(seconds)
      @now = now_proc
      @start_time = @now.call
    end

    def passed?
      return true if @duration.zero?

      @now.call - @start_time >= @duration
    end

    def reset
      @start_time = @now.call
      nil
    end

    private

    def normalize_duration(seconds)
      return 0.0 if seconds.nil? || seconds.to_f.zero?
      raise ArgumentError, "duration must be non-negative" if seconds.to_f.negative?

      seconds.to_f
    end
  end
end
