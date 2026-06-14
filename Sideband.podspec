Pod::Spec.new do |s|
	s.name = "Sideband"
	s.version = "1.1.0-beta.3"
	s.summary = "Sideband iOS SDK"
	s.description = "Sideband helps iOS apps collect lightweight in-app feedback pulses and send product events to Sideband."
	s.homepage = "https://github.com/SidebandAI/sideband-ios"
	s.license = { :type => "Proprietary" }
	s.author = { "SidebandAI" => "support@sideband.ai" }
	s.platform = :ios, "15.0"
	s.swift_versions = ["6.2"]
	s.source = {
		:git => "git@github.com:SidebandAI/sideband-ios.git",
		:tag => s.version.to_s,
	}
	s.prepare_command = "unzip -q -o Sideband.xcframework.zip"
	s.vendored_frameworks = "Sideband.xcframework"
end
