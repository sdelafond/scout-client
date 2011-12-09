# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "scout/version"

Gem::Specification.new do |s|
  s.name        = "scout"
  s.version     = Scout::VERSION
  s.authors     = ["Andre Lewis", "Derek Haynes", "James Edward Gray II"]
  s.email = "support@scoutapp.com"
  s.rubyforge_project = "scout"
  s.homepage = "http://scoutapp.com"
  s.summary = "Web-based monitoring, reporting, and alerting for your servers, clusters, and applications."
  s.description = <<END_DESC
Scout makes monitoring and reporting on your web applications as flexible and simple as possible.
END_DESC

  s.rubyforge_project = "scout"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  s.add_runtime_dependency "elif"
end
