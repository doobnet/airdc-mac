import Foundation
import Testing
import UtilityKit

@testable import WebSocketKit

final class WebSocketTests {
  /*class Transport: WebSocketKit.Transport {
    struct Called {
      var resume = 0
      var cancel: [(closeCode: CloseCode, reason: Data?)] = []
    }

    var called = Called()
    var closeCode: CloseCode = .invalid
    var delegate: (any URLSessionTaskDelegate)?

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
      called.cancel.append((closeCode, reason))
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

  @Test("it disconnects the web socket")
  func disconnect_transport() async throws {
    let transport = Transport()
    let webSocket = newWebSocket(transport: transport)

    try await webSocket.connect()
    webSocket.disconnect()

    #expect(transport.called.cancel.count == 1)
    #expect(
      transport.called.cancel.first! == (closeCode: .normalClosure, reason: nil)
    )
  }

  @Test("it updates the state to 'disconnected'")
  func disconnect_state() async throws {
    let transport = Transport()
    let webSocket = newWebSocket(transport: transport)

    try await webSocket.connect()
    webSocket.disconnect()

    #expect(
      webSocket.state
        == .disconnected(closeCode: .normalClosure, closeReason: nil)
    )
  }*/

  deinit {
    print("deinit in test")
    if serverProcess.isRunning {
      serverProcess.terminate()
      serverProcess.waitUntilExit()
    }
  }

  lazy var stdin = Pipe()

  lazy var serverProcess = {
    let process = Process()

    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/bun")
    process.arguments = ["--port", "8080", "-"]
    process.standardInput = stdin
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    process.environment = ["NO_COLOR": "1"]

    stdin.fileHandleForWriting.write(javaScriptServer.data(using: .utf8)!)
    stdin.fileHandleForWriting.closeFile()

    return process
  }()

  let javaScriptServer = """
    Bun.serve({
      fetch(req, server) {
        if (!server.upgrade(req))
          return new Response("Upgrade failed", { status: 500 });
      },
      websocket: {
        message(ws, message) { ws.send(message) }
      }
    })
  """

  func newWebSocket() async throws -> WebSocket {
    try serverProcess.run()

    let webSocket = WebSocket(url: URL(string: "ws://localhost:8080")!)
    try await Task.sleep(for: .seconds(1))
    try await webSocket.connect()

    return webSocket
  }

  @Test("end to end test")
  func endToEnd() async throws {
    let webSocket = try await newWebSocket()

    try await webSocket.send("first message")
    let result = try await webSocket.receive()

    #expect(String(data: result, encoding: .utf8)! == "first message")
  }

  @Test("end to end async sequence test")
  func asyncSequence() async throws {
    let webSocket = try await newWebSocket()

    try await webSocket.send("first message")
    try await webSocket.send("second message")

    let result = try await webSocket
      .prefix(2)
      .map { String(data: $0, encoding: .utf8)! }
      .reduce(into: Array()) { $0.append($1) }

    #expect(result == ["first message", "second message"])
  }

  @Test("state update handler")
  func stateUpdateHandler() async throws {
    let webSocket = try await newWebSocket()
  }
}
