require 'stringio'

module Rack

  # Ensures env['rack.input'] is never nil, restoring Rack 2 behavior for downstream code.
  class BodyNormalizer
    def initialize(app)
      @app = app
    end

    def call(env)
      # Only coerce when Rack 3 provided nil (i.e., definitively no body).
      env['rack.input'] ||= StringIO.new

      # Optional: keep Content-Length consistent if it was missing
      # This isn't strictly necessary, but can avoid surprises in some parsers.
      if env['rack.input'].is_a?(StringIO) && env['CONTENT_LENGTH'].nil?
        env['CONTENT_LENGTH'] = '0'
      end

      @app.call(env)
    end
  end
end
