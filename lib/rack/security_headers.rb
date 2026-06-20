# frozen_string_literal: true


module Rack

  # Rack middleware that enforces the OWASP-recommended set of HTTP security
  # response headers to every response passing through the middleware.
  #
  class SecurityHeaders
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)

      headers['X-XSS-Protection'] = '0'
      headers['X-Frame-Options'] = 'deny'
      headers['X-Content-Type-Options'] = 'nosniff'
      headers['X-Permitted-Cross-Domain-Policies'] = 'none'
      headers['Referrer-Policy'] = 'no-referrer'
      headers['Cross-Origin-Embedder-Policy'] = 'require-corp'
      headers['Cross-Origin-Opener-Policy'] = 'same-origin'
      headers['Cross-Origin-Resource-Policy'] = 'same-origin'
      headers['X-DNS-Prefetch-Control'] = 'off'
      headers['Cache-Control'] = 'no-store, max-age=0'

      [status, headers, body]
    end
  end
end

