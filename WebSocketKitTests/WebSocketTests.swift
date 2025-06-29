import Foundation
import Testing
import UtilityKit

@testable import WebSocketKit

struct WebSocketTests {
  class Transport: WebSocketKit.Transport {
    struct Called {
      var resume = 0
    }

    var called = Called()
    var closeCode: CloseCode = .invalid

    func receive() async throws -> URLSessionWebSocketTask.Message {
      return .string("test message")
    }

    func receive(
      completionHandler: @escaping (
        Result<URLSessionWebSocketTask.Message, any Error>
      ) -> Void
    ) {

    }

    func send(_ message: URLSessionWebSocketTask.Message) {

    }

    func cancel(
      with closeCode: URLSessionWebSocketTask.CloseCode,
      reason: Data?
    ) {

    }

    func resume() {
      called.resume += 1
    }
  }

  func newWebSocket(
    transport: Transport
  ) -> WebSocket {
    return WebSocket(transport: transport, logger: Logging.disabledLogger)
  }

  @Test("it connects the web socket")
  func connect_transport() async throws {
    let transport = Transport()
    let webSocket = newWebSocket(transport: transport)
    
    try await webSocket.connect()

    #expect(transport.called.resume == 1)
  }

  @Test("it updates the state to 'connecting'")
  func connect_state() async throws {
    let transport = Transport()
    let webSocket = newWebSocket(transport: transport)

    try await webSocket.connect()

    #expect(webSocket.state == .connecting)
  }
}
