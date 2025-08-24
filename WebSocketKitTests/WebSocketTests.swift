import Foundation
import Testing
import UtilityKit

@testable import WebSocketKit

final class WebSocketTests {
  actor State {
    private var _stateHandled = false

    var isHandled: Bool { _stateHandled }

    func stateHandled() {
      _stateHandled = true
    }
  }

  var server: WebSocketServer!

  func newWebSocket(
    stateUpdateHandler: @escaping WebSocket.StateUpdateHandler = { _ in },
    autoReconnect: WebSocket.AutoReconnect = WebSocket.AutoReconnect()
  ) async throws -> WebSocket {
    server = try await WebSocketServer(
      tls: false,
      requiredInterfaceType: .loopback
    ).start()

    let url = buildURL(scheme: "ws", host: "localhost", port: server.port!)
    let webSocket = WebSocket(url: url, autoReconnect: autoReconnect)
    webSocket.stateUpdateHandler = stateUpdateHandler

    return webSocket
  }

  @Test("end to end test")
  func endToEnd() async throws {
    let result = try await newWebSocket()
      .send("first message")
      .receive()

    #expect(String(data: result, encoding: .utf8)! == "first message")
  }

  @Test("end to end async sequence test")
  func asyncSequence() async throws {
    let webSocket = try await newWebSocket()
      .send("first message")
      .send("second message")

    let result =
      try await webSocket
      .prefix(2)
      .map { String(data: $0, encoding: .utf8)! }
      .reduce(into: Array()) { $0.append($1) }

    #expect(result == ["first message", "second message"])
  }

  @Test("state update handler")
  func stateUpdateHandler() async throws {
    let state = State()

    let webSocket = try await newWebSocket { newState in
      switch newState {
      case .preparing:
        Task {
          await state.stateHandled()
        }
      default:
        break
      }
    }

    try await webSocket.send("first message")

    #expect(await state.isHandled)
  }

//  @Test("automatically reconnect on failure")
//  func autoReconnect() async throws {
//    let webSocket = try await newWebSocket(
//      autoReconnect: .init(enabled: true, delay: .milliseconds(1))
//    )
//
//    try await webSocket.send("first message").receive()
//
//    await server.stop()
//    try await server.start()
//
//    let result = try await webSocket
//      .send("second message")
//      .receive()
//
//    #expect(String(data: result, encoding: .utf8)! == "second message")
//  }
}
