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

  func send(_ message: URLSessionWebSocketTask.Message) async throws

  func cancel(
    with closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  )
}

typealias InternalStream = AsyncThrowingStream<
  URLSessionWebSocketTask.Message, Error
>

class WebSocket: NSObject, AsyncSequence {
  typealias AsyncIterator = InternalStream.Iterator
  typealias Element = URLSessionWebSocketTask.Message

  enum Error: Swift.Error {
    case clientError(code: Int, message: String)
    case serverError(code: Int, message: String)
    case timeout
  }

  enum State: Equatable {
    case readyToConnect
    case disconnected(
      closeCode: Transport.CloseCode,
      closeReason: Data? = nil
    )
    case connecting
    case connected(protocol: String? = nil)

    var isConnected: Bool {
      switch self {
      case .connected: return true
      default: return false
      }
    }

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
  private var receivingContinuation: InternalStream.Continuation?
  private var connectionContinuation: CheckedContinuation<Void, Swift.Error>?

  private lazy var stream: InternalStream = {
    InternalStream { continuation in
      self.receivingContinuation = continuation

      Task {
        var isAlive = true

        while isAlive && self.state.isConnected {
          do {
            let value = try await socket.receive()
            continuation.yield(value)
          } catch {
            continuation.finish(throwing: error)
            isAlive = false
          }
        }
      }
    }
  }()

  init(transport: Transport, logger: Logger = Logging.newLogger()) {
    socket = transport
    self.logger = logger
    super.init()
    socket.delegate = self
  }

  convenience init(url: URL, timeout: TimeInterval = 60) {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = timeout
    configuration.waitsForConnectivity = true

    let session = URLSession(
      configuration: configuration,
      delegate: nil,
      delegateQueue: nil
    )
    let task = session.webSocketTask(with: url)

    self.init(transport: task)
  }

  deinit {
    disconnect()
  }

  func connect(timeout: TimeInterval = 60) async throws {
    logger.debug("connect")
    socket.resume()
    state = .connecting
  }

  func disconnect() {
    logger.debug("disconnect")

    if state.isConnected {
      state = .disconnected(closeCode: .normalClosure)
      socket.cancel(with: .normalClosure, reason: nil)
    }

    receivingContinuation?.finish()
    receivingContinuation = nil
    connectionContinuation?.resume(throwing: CancellationError())
    connectionContinuation = nil
  }

  func receive() async throws -> URLSessionWebSocketTask.Message {
    logger.debug("receive")
    return try await socket.receive()
  }

  func send(_ message: Foundation.Data, operation: String = #function) async throws {
    try await socket.send(.data(message))
  }

  func send(_ message: String, operation: String = #function) async throws {
    try await socket.send(.string(message))
  }

  @available(macOS 14, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  func makeAsyncIterator() -> InternalStream.Iterator {
    stream.makeAsyncIterator()
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
    connectionContinuation?.resume()
    connectionContinuation = nil
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Swift.Error?
  ) {

    if let error = error {
      logger.error("WebSocket task completed with error: \(error)")

      state = .disconnected(
        closeCode: .abnormalClosure,
        closeReason: error.localizedDescription.data(using: .utf8)
      )
    } else {
      logger.debug("WebSocket task completed successfully")

      state = .disconnected(closeCode: .normalClosure)
    }
  }
}
