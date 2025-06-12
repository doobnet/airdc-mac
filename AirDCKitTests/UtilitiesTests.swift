@testable import AirDCKit
import Foundation
import XCTest

class UtilitiesTests: XCTestCase {
    func testBuildURL() {
        let actual = URL(string: "wss://foo:1234/bar/abc")!
        let result = buildURL(host: "foo", port: 1234, path: "/bar/abc")
        XCTAssertEqual(result, actual)
    }
}
