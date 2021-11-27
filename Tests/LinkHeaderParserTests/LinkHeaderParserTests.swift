/*
MIT License

Copyright © 2018 François Lamboley <francois.lamboley@frostland.fr>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. */

import XCTest
@testable import LinkHeaderParser



final class LinkHeaderParserTests: XCTestCase {
	
	func testBasicHeaderParse() {
		let header = #"<https://apple.com/>; rel=about"#
		let expectedLinkValue = LinkValue(link: URL(string: "https://apple.com/")!, context: nil, rel: ["about"], rev: nil, hreflang: nil, mediaQuery: nil, title: nil, type: nil, extensions: [:])
		XCTAssertEqual(LinkHeaderParser.parseLinkHeader(header, defaultContext: nil, contentLanguageHeader: nil, lax: true), [expectedLinkValue])
	}
	
	func testWeirdHeaderParse() {
		let header = #"<http://example.com/;;;,,,>; rel="next;;;,,, next"; a-zA-Z0-9!#$&+-.^_|~=!#$%&'*+-.0-9a-zA-Z^_|~; title*=UTF-8'de'N%c3%a4chstes%20Kapitel"#
		let expectedLinkValue = LinkValue(link: URL(string: "http://example.com/;;;,,,")!, context: nil, rel: ["next;;;,,,", "next"], rev: nil, hreflang: nil, mediaQuery: nil, title: "Nächstes Kapitel", type: nil, extensions: ["a-za-z0-9!#$&+-.^_|~": ["!#$%&'*+-.0-9a-zA-Z^_|~"]])
		XCTAssertEqual(LinkHeaderParser.parseLinkHeader(header, defaultContext: nil, contentLanguageHeader: nil, lax: true), [expectedLinkValue])
	}
	
	func testInvalidLinkLaxParsing() {
		let header = #"<https://api.github.com/users?per_page=21&since=31>; rel="next", <https://api.github.com/users{?since}>; rel="first""#
		let expectedLinkValues = [LinkValue(link: URL(string: "https://api.github.com/users?per_page=21&since=31")!, context: nil, rel: ["next"], rev: nil, hreflang: nil, mediaQuery: nil, title: nil, type: nil, extensions: [:])]
		XCTAssertEqual(LinkHeaderParser.parseLinkHeader(header, defaultContext: nil, contentLanguageHeader: nil, lax: true), expectedLinkValues)
	}
	
	func testInvalidLinkStrictParsing() {
		let header = #"<https://api.github.com/users?per_page=21&since=31>; rel="next", <https://api.github.com/users{?since}>; rel="first""#
		XCTAssertEqual(LinkHeaderParser.parseLinkHeader(header, defaultContext: nil, contentLanguageHeader: nil, lax: false), nil)
	}
	
	static var allTests = [
		("testBasicHeaderParse", testBasicHeaderParse),
		("testWeirdHeaderParse", testWeirdHeaderParse),
		("testInvalidLinkLaxParsing", testInvalidLinkLaxParsing),
		("testInvalidLinkStrictParsing", testInvalidLinkStrictParsing)
	]
	
}
