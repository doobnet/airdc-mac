@testable import AirDCKit
import Foundation
import XCTest

import Mockingbird

class WebSocketConnectionTests: XCTestCase {
    struct Transport: AirDCKit.Transport {
        typealias Resume = () -> Void
        typealias Receive = () async throws -> URLSessionWebSocketTask.Message
        typealias Send = (URLSessionWebSocketTask.Message, @escaping (Error?) -> Void) -> Void

        private let resume_: Resume?
        private let receive_: Receive?
        private let send_: Send?

        init(resume: Resume? = nil, receive: Receive? = nil, send: Send? = nil) {
            resume_ = resume
            receive_ = receive
            send_ = send
        }

        func resume() {
            guard let resume_ else { return }
            resume_()
        }

        func receive() async throws -> URLSessionWebSocketTask.Message {
            guard let receive_ else { return URLSessionWebSocketTask.Message.string("") }
            return try await receive_()
        }

        func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping (Error?) -> Void) {
            guard let send_ else { return }
            send_(message, completionHandler)
        }
    }

//    func testSend() {
//        let transport = Transport(resume: {})
//        transport.expectToReceive(.receive, with: "foo")
//    }
}
