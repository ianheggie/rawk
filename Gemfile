source 'https://rubygems.org'

# Specify your gem's dependencies in rawk_log.gemspec
gemspec

platforms :ruby_18 do
  gem 'rake', '< 11.0'
end
platforms :ruby_22, :ruby_23 do
  gem 'test-unit'
  gem 'minitest'
end

platforms :ruby_18 do
  # mime-types 2.0 requires Ruby version >= 1.9.2
  gem 'mime-types', '< 2.0'
end
platforms :ruby_19, :jruby do
  # mime-types 3.0 requires Ruby version >= 2.0
  gem 'mime-types', '< 3.0'
end

gem 'coveralls', :require => false, :group => :development
