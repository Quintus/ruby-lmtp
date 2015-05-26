# coding: utf-8
require_relative "lib/lmtp"

GEMSPEC = Gem::Specification.new do |spec|
  spec.name = "lmtp"
  spec.version = LmtpServer::VERSION
  spec.date = Time.now.strftime("%Y-%m-%d")
  spec.summary = "LMTP server library for Ruby"
  spec.description = <<EOF
This library allows your application to act as an LMTP endpoint
so you can have MTAs like Postfix relay mail directly to your
application.
EOF
  spec.authors = ["Marvin Gülker"]
  spec.email = "quintus@quintilianus.eu"
  spec.files = Dir["lib/**/*.rb", "README.rdoc", "LICENSE"]
  spec.homepage = "https://quintus.github.io/ruby-lmtp/"
  spec.license = "BSD"

  spec.platform = Gem::Platform::RUBY
  spec.required_ruby_version = ">= 2.0.0"
  spec.has_rdoc = true
  spec.extra_rdoc_files = %w[README.rdoc LICENSE]
  spec.rdoc_options << "-t" << "LMTP library for Ruby" << "-m" << "README.rdoc"
end
