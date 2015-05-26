# coding: utf-8
GEMSPEC = Gem::Specification.new do |spec|
  spec.name = "lmtp"
  spec.version = "0.0.0"
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
  spec.homepage = "http://todo.invalid"
  spec.license = "BSD"
end
