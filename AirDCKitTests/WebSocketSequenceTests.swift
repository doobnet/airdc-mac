import Foundation
import XCTest

import SwiftMock

@testable import AirDCKit

class WebSocketSequenceTests: TestCase {
    lazy var transport = TransportMock()
    lazy var continuation = ContinuableMock()
    lazy var sequence = WebSocketSequence(
        task: transport,
        continuation: continuation
    )

    override func setUp() {
        super.setUp()

        when(transport.$resume()).thenReturn()
        when(continuation.$finish()).thenReturn()
    }

    func test_init_itResumesTheTask() {
        let _ = sequence // create sequence
        verify(transport).resume()
    }

    func test_cancel_itCancelsTheTask() async throws {
        when(transport.$cancel()).thenReturn()
        try await sequence.cancel()
        verify(transport).cancel()
    }

    func test_cancel_itFinishesTheContinuation() async throws {
        when(transport.$cancel()).thenReturn()
        try await sequence.cancel()
        verify(continuation).finish()
    }

    func test_sequence_invalidCloseCode() async throws {
        let message = URLSessionWebSocketTask.Message.string("")
        let result = Result { message }

        when(transport.$closeCodeGetter()).thenReturn(.invalid)
        when(continuation.$finish()).thenReturn()
        when(transport.$receive(completionHandler: any())).thenAnswer {
            $0(result)
        }

        for try await message in sequence {
            print(message)
            try await sequence.cancel()
        }

        verify(continuation).finish()
    }
}
