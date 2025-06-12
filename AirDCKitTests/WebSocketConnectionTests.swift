import Foundation
import XCTest

import SwiftMock

@testable import AirDCKit

class WebSocketConnectionTests: TestCase {
    let json = """
        {"callback_id":548357391,"code":200}
    """

    lazy var transport = TransportMock()
    lazy var continuations = ContinuationsMock()
    lazy var connection = WebSocketConnection(
        transport: transport,
        continuations: continuations
    )

    override func setUp() {
        connection.disconnect()
    }

    func testConnect_resume() throws {
        when(transport.$resume()).thenReturn()
        when(transport.$receive()).thenReturn(.string(json))
        when(continuations.$resumeContinuation(withId: any(), returning: any()))
            .thenReturn(true)

        try connection.connect()
        connection.disconnect()

        verify(transport).resume()
    }
}
