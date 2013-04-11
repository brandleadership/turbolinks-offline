Gem::Specification.new do |s|
  s.name    = 'turbolinks-offline'
  s.version = '0.0.1'
  s.author  = 'Felipe Kaufmann'
  s.email   = 'developers@screenconcept.ch'
  s.summary = 'Turbolinks makes following links in your web application faster (use with Rails Asset Pipeline). This also caches the pages in localStorage'
  s.files   = Dir["lib/assets/javascripts/*.js.coffee", "lib/turbolinks.rb", "README.md", "MIT-LICENSE", "test/*"]
  
  s.add_dependency 'coffee-rails'
end
