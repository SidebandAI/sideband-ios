Pod::Spec.new do |s|
	s.name = "Sideband"
	s.version = "1.1.0-beta.1"
	s.summary = "Sideband iOS SDK"
	s.description = "Sideband helps iOS apps collect lightweight in-app feedback pulses and send product events to Sideband."
	s.homepage = "https://github.com/SidebandAI/sideband-ios"
	s.license = { :type => "Proprietary" }
	s.author = { "SidebandAI" => "support@sideband.ai" }
	s.platform = :ios, "15.0"
	s.swift_versions = ["6.2"]
	s.source = {
		:http => "https://github.com/SidebandAI/sideband-ios/releases/download/1.1.0-beta.1/Sideband.xcframework.zip",
		:sha256 => "9b59ae82e45daa6948c9677d00426e3c7cac7767697a4d14be0ef774572e7310",
	}
	s.vendored_frameworks = "Sideband.xcframework"
end
