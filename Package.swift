// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription



let package = Package(
	name: "LinkHeaderParser",
	products: [
		.library(name: "LinkHeaderParser", targets: ["LinkHeaderParser"])
	],
	targets: [
		.target(name: "LinkHeaderParser", dependencies: []),
		.testTarget(name: "LinkHeaderParserTests",dependencies: ["LinkHeaderParser"])
	]
)
