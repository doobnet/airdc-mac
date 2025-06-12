import Foundation
import XCTest

import SwiftMock
import SwiftMockConfiguration

@objc class TestSuite: NSObject {
    override init() {
        testFailureReport = { XCTFail($0, file: $1, line: $2) }
    }
}

class TestCase: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        SwiftMockConfiguration.setUp()
    }

    override func tearDown() {
        SwiftMockConfiguration.tearDown()
        super.tearDown()
    }
}
