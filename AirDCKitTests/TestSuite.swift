import Foundation
import XCTest

import SwiftMock

@objc class TestSuite: NSObject {
    override init() {
        testFailureReport = { XCTFail($0) }
    }
}

class TestCase: XCTestCase {
    override func tearDown() {
        cleanUpMock()
    }
}
