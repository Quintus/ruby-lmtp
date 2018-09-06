require "rubygems/package_task"
require "rdoc/task"

load("lmtp.gemspec")
Gem::PackageTask.new(GEMSPEC).define

Rake::RDocTask.new do |rd|
  rd.rdoc_files.include("lib/**/*.rb", "*.rdoc", "LICENSE")
  rd.title = "LMTP library for Ruby"
  rd.main = "README.rdoc"
  rd.rdoc_dir = "doc"
  rd.generator = "emerald"
end

desc "Run the tests."
task :test do
  cd "test" do
    ruby "test_lmtp.rb"
  end
end
