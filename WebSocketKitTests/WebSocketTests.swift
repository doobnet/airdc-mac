import Foundation
import Testing
import UtilityKit

@testable import WebSocketKit

final class WebSocketTests {
  deinit {
    guard serverProcess.isRunning else { return }

    serverProcess.terminate()
    serverProcess.waitUntilExit()
  }

  actor StateHandler {
    private var _stateHandled = false

    var isHandled: Bool { _stateHandled }

    func stateHandled() {
      _stateHandled = true
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

  func newWebSocket(
    stateUpdateHandler: @escaping WebSocket.StateUpdateHandler = { _ in }
  ) async throws -> WebSocket {
    try serverProcess.run()

    let webSocket = WebSocket(url: URL(string: "ws://localhost:8080")!)
    webSocket.stateUpdateHandler = stateUpdateHandler
    try await Task.sleep(for: .seconds(1))
    try await webSocket.connect()

    return webSocket
  }

  @Test("end to end test")
  func endToEnd() async throws {
    let server = WebSocketServer(tls: false)
    try await server.start()

    let url = buildURL(scheme: "ws", host: "localhost", port: server.port!)
    let webSocket = WebSocket(url: url)
    try await webSocket.connect()

    try await webSocket.send("first message")
    let result = try await webSocket.receive()

    #expect(String(data: result, encoding: .utf8)! == "first message")
  }

  @Test("end to end async sequence test")
  func asyncSequence() async throws {
    let webSocket = try await newWebSocket()

    try await webSocket.send("first message")
    try await webSocket.send("second message")

    let result =
      try await webSocket
      .prefix(2)
      .map { String(data: $0, encoding: .utf8)! }
      .reduce(into: Array()) { $0.append($1) }

    #expect(result == ["first message", "second message"])
  }

  @Test("state update handler")
  func stateUpdateHandler() async throws {
    let stateHandler = StateHandler()

    let _ = try await newWebSocket { state in
      switch state {
      case .preparing:
        Task {
          await stateHandler.stateHandled()
        }
      default:
        break
      }
    }

    #expect(await stateHandler.isHandled)
  }
}

