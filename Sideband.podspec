Pod::Spec.new do |s|
	s.name = "Sideband"
	s.version = "1.4.0-rc.1"
	s.summary = "Sideband iOS SDK"
	s.description = "Sideband helps iOS apps collect lightweight in-app feedback pulses and send product events to Sideband."
	s.homepage = "https://github.com/SidebandAI/sideband-ios"
	s.license = {
		:type => "Proprietary",
		:text => "Copyright SidebandAI. All rights reserved.",
	}
	s.author = { "SidebandAI" => "support@sideband.ai" }
	s.platform = :ios, "15.0"
	s.module_name = "SidebandWebView"
	s.swift_versions = ["6.2"]
	s.source = {
		:http => "https://github.com/SidebandAI/sideband-ios/releases/download/1.4.0-rc.1/Sideband-CocoaPods-1.4.0-rc.1.zip",
	}
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
