import Foundation
import OSLog
import SwiftMock
import UtilityKit

@Mock public protocol Transport {
  typealias CloseCode = URLSessionWebSocketTask.CloseCode

  var closeCode: CloseCode { get }
  var delegate: (any URLSessionTaskDelegate)? { get set }

  func resume()
  func receive() async throws -> URLSessionWebSocketTask.Message

  func send(_ message: URLSessionWebSocketTask.Message)

  func cancel(
    with closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  )
}

class WebSocket: NSObject {
  enum Error: Swift.Error {
    case clientError(code: Int, message: String)
    case serverError(code: Int, message: String)
  }

  enum State: Equatable {
    case readyToConnect
    case disconnected(
      closeCode: Transport.CloseCode,
      closeReason: Data? = nil
    )
    case connecting
    case connected(protocol: String? = nil)

    static func == (lhs: State, rhs: State) -> Bool {
      switch (lhs, rhs) {
      case (.readyToConnect, .readyToConnect):
        return true
      case (
        .disconnected(let lhsCode, let lhsReason),
        .disconnected(let rhsCode, let rhsReason)
      ):
        return lhsCode == rhsCode && lhsReason == rhsReason
      case (.connecting, .connecting):
        return true
      case (.connected(let lhsProtocol), .connected(let rhsProtocol)):
        return lhsProtocol == rhsProtocol
      default:
        return false
      }
    }
  }

  private(set) var state = State.readyToConnect
  private var socket: Transport
  private let logger: Logger

  init(transport: Transport, logger: Logger = Logging.newLogger()) {
    socket = transport
    self.logger = logger
    super.init()
    socket.delegate = self
  }

  func connect() async throws {
    logger.debug("connect")
    socket.resume()
    state = .connecting
  }

  func disconnect() {
    logger.debug("disconnect")
    state = .disconnected(closeCode: .normalClosure)
    socket.cancel(with: .normalClosure, reason: nil)
  }

  func receive() async throws -> URLSessionWebSocketTask.Message {
    logger.debug("receive")
    return try await socket.receive()
  }

  func send(_ message: Foundation.Data, operation: String = #function) async {
    socket.send(.data(message))
  }

  func send(_ message: String, operation: String = #function) async {
    socket.send(.string(message))
  }
}

extension WebSocket: URLSessionWebSocketDelegate {
  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    logger.debug(
      "WebSocket closed with code: \(String(describing: closeCode)), reason: \(String(describing: reason))"
    )
    state = .disconnected(closeCode: closeCode, closeReason: reason)
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    logger.debug(
      "WebSocket opened with protocol: \(String(describing: `protocol`))"
    )
    state = .connected(protocol: `protocol`)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Swift.Error?
  ) {
    state = .disconnected(
      closeCode: .abnormalClosure,
      closeReason: error?.localizedDescription.data(using: .utf8)
    )
  }
}
