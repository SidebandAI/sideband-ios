Pod::Spec.new do |s|
	s.name = "Sideband"
	s.version = "1.3.0"
	s.summary = "Sideband iOS SDK"
	s.description = "Sideband helps iOS apps collect lightweight in-app feedback pulses and send product events to Sideband."
	s.homepage = "https://github.com/SidebandAI/sideband-ios"
	s.license = { :type => "Proprietary" }
	s.author = { "SidebandAI" => "support@sideband.ai" }
	s.platform = :ios, "15.0"
	s.swift_versions = ["6.2"]
	s.source = {
		:git => "https://github.com/SidebandAI/sideband-ios.git",
		:tag => "1.3.0",
	}
	s.prepare_command = "unzip -q -o Sideband.xcframework.zip"
	s.default_subspecs = "Core"
	s.subspec "Core" do |core|
		core.vendored_frameworks = "Sideband.xcframework"
	end
	s.subspec "WebView" do |webview|
		webview.dependency "Sideband/Core"
		webview.source_files = "Sources/SidebandWebView/**/*.swift"
		webview.frameworks = "WebKit"
	end
end
