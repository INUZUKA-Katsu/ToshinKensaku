# config/puma.rb
workers Integer(ENV.fetch('WEB_CONCURRENCY', 2))
threads_count = Integer(ENV.fetch('RACK_THREADS', 5))
threads threads_count, threads_count

preload_app!

rackup 'config.ru'  # Rack アプリの場合は明示的に指定

port ENV.fetch('PORT', 9292)  # Heroku では $PORT を使う
environment ENV.fetch('RACK_ENV', 'development')