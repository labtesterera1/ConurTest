# frozen_string_literal: true

source 'https://rubygems.org'

# ruby=ruby-3.4
# ruby-gemset=conjur

if File.exist?('/base/Gemfile')
  # Include Gemfile from the base image (container use case)
  eval_gemfile '/base/Gemfile'
else
  # If /base does not exist, we are probably installing
  # gems in a local development environment. In that case, try to include gems
  # from the local base directory (not in git, created during dev/start).
  eval_gemfile 'base/Gemfile'
end

gem 'base58'
gem 'http', '~> 4.2'
gem 'iso8601'
gem 'mustache'
gem 'net-imap'
gem 'sequel-pg_advisory_locking'
gem 'sequel-postgres-schemata', require: false
gem 'sequel-rails'
gem 'base32-crockford'
gem 'bcrypt'
gem 'listen'
gem 'slosilo', '~> 3.0'
gem 'syslog'

gem 'loofah', '>= 2.2.3'
gem 'conjur-policy-parser', path: 'gems/policy-parser'
gem 'conjur-rack', path: 'gems/conjur-rack'
gem 'rack-rewrite'
gem 'dry-validation'

group :production do
  gem 'rails_12factor'
end

# K8S Authenticator
gem 'event_emitter'
gem 'kubeclient'
gem 'websocket'

# OIDC Authenticator
gem 'openid_connect', '~> 2.0'

gem 'json_schemer'
gem 'prometheus-client'

group :development, :test do
  gem 'csr'
  gem 'database_cleaner', '~> 1.8'
  gem 'debug' # For VSCode debugging
  gem 'faye-websocket'
  gem 'parallel_tests'
  gem 'rails_layout'
  gem 'rake_shared_context'
  gem 'rspec-core'
  gem 'table_print'
  gem 'webrick'
end

group :development do
  # NOTE: minor version of this needs to match codeclimate channel
  gem 'rubocop', '>= 1.57.0', require: false

  gem 'reek', require: false
  gem 'rubocop-checkstyle_formatter', '>= 0.5.0', require: false # for Jenkins
end

group :test do
  gem 'haikunator', '~> 1' # for generating random names in tests
end
