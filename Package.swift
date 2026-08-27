// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "Sideband",
	platforms: [
		.iOS(.v15),
	],
	products: [
		.library(
			name: "Sideband",
			targets: ["Sideband"]
		),
		.library(
			name: "SidebandWebView",
			targets: ["SidebandWebView"]
		),
	],
	targets: [
		.binaryTarget(
			name: "Sideband",
			path: "Sideband.xcframework.zip"
		),
		.target(
			name: "SidebandWebView",
			dependencies: ["Sideband"],
			path: "Sources/SidebandWebView"
		),
	]
)
