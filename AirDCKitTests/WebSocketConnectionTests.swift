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

    func test_connect_resume() async throws {
        when(transport.$resume()).thenReturn()
        when(transport.$receive()).thenReturn(.string(json))
        when(continuations.$resumeContinuation(withId: any(), returning: any()))
            .thenReturn(true)

        try await connection.connect()
        await connection.disconnect()

        verify(transport).resume()
    }

    func test_connect_receive() async throws {
        when(transport.$resume()).thenReturn()
        when(transport.$receive()).thenReturn(.string(json))
        when(continuations.$resumeContinuation(withId: any(), returning: any()))
            .thenReturn(true)

        try await connection.connect()
        await connection.disconnect()

        verify(transport).receive()
    }
}
