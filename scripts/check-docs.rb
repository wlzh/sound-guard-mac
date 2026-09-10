require 'pathname'
root = Pathname.new(__dir__).parent
version = (root / 'VERSION').read.strip
build = (root / 'BUILD_NUMBER').read.strip
abort 'Invalid version' unless version.match?(/\A\d+\.\d+\.\d+\z/) && build.match?(/\A[1-9]\d*\z/)
files = %w[README.md LICENSE CHANGELOG.md CONTRIBUTING.md SECURITY.md docs/README.md docs/INSTALL.md docs/USER_GUIDE.md docs/ABOUT.md docs/TESTING.md docs/PERFORMANCE.md docs/prd/README.md]
files += %w[prd design dev plan].map { |name| "docs/prd/v#{version}/#{name}.md" }
files << "docs/releases/v#{version}.md"
files.each { |file| abort "Missing #{file}" unless (root / file).file? && (root / file).size > 0 }
policy = (root / 'Sources/GuardCore/Policy.swift').read
abort 'Version constant mismatch' unless policy.include?("public static let current = \"#{version}\"")
abort 'Build constant mismatch' unless policy.include?("public static let build = \"#{build}\"")
plist = (root / 'Resources/Info.plist').read
abort 'Plist version mismatch' unless plist.include?("<key>CFBundleShortVersionString</key><string>#{version}</string>")
abort 'Plist build mismatch' unless plist.include?("<key>CFBundleVersion</key><string>#{build}</string>")
abort 'Changelog mismatch' unless (root / 'CHANGELOG.md').read.include?("## [#{version}]")
abort 'Install archive mismatch' unless (root / 'docs/INSTALL.md').read.include?("SoundGuard-v#{version}-macos-universal.zip")
%w[prd design dev plan].each do |name|
  abort "Wrong heading #{name}" unless (root / "docs/prd/v#{version}/#{name}.md").read.lines.first.include?("v#{version}")
end
abort 'Missing acceptance criteria' unless (root / "docs/prd/v#{version}/prd.md").read.scan(/^- \[[ x]\] A\d\d /).length == 34
markdown = Dir.glob("#{root}/{*.md,docs/**/*.md}")
markdown.each do |file|
  File.read(file).scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |link|
    next if link.match?(/\A(?:https?:|mailto:|#)/)
    target = File.expand_path(link.split('#').first, File.dirname(file))
    abort "Broken link #{file}: #{link}" unless File.exist?(target)
  end
end
tests = (root / 'Tests/GuardCoreTests/GuardTests.swift').read
count = tests.scan(/func test\w+\(/).length
abort 'Test report count mismatch' unless (root / 'docs/TESTING.md').read.include?("当前 #{count} 项回归")
tests.scan(/func (test\w+)\(/).flatten.each do |name|
  abort "Unregistered test #{name}" unless tests.match?(/Tests\.#{name}\b/)
end
abort 'MIT missing' unless (root / 'LICENSE').read.start_with?('MIT License')
puts "DOCS_CHECK=PASS; VERSION=#{version}; BUILD=#{build}; MARKDOWN=#{markdown.length}; ACCEPTANCE=34"
