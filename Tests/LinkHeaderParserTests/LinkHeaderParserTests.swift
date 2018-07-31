import XCTest
@testable import LinkHeaderParser

final class LinkHeaderParserTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(LinkHeaderParser().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
