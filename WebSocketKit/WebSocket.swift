import Foundation
import Network
import OSLog
import UtilityKit

public protocol Transport {
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

typealias InternalStream = AsyncThrowingStream<Data, Error>

class WebSocket: AsyncSequence {
  typealias AsyncIterator = InternalStream.Iterator
  typealias Element = InternalStream.Element

  enum Error: Swift.Error {
    case clientError(code: Int, message: String)
    case serverError(code: Int, message: String)
    case timeout
  }

  enum State: Equatable {
    case readyToConnect
    case disconnected(
      closeCode: Transport.CloseCode,
      closeReason: String? = nil
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
  private let logger: Logger
  private let url: URL
  private let endpoint: NWEndpoint
  private var streamContinuation: InternalStream.Continuation?
  private var sendContinuation: CheckedContinuation<Void, Swift.Error>?
  private var receiveContinuation: CheckedContinuation<Data, Swift.Error>?
  private var connectionContinuation: CheckedContinuation<Void, Swift.Error>?
  private var connection: NWConnection?
  private let queue = DispatchQueue(label: "WebSocketQueue")

  init(url: URL, logger: Logger = Logging.newLogger()) {
    self.logger = logger
    self.url = url
    self.endpoint = NWEndpoint.url(url)
  }

  deinit {
    disconnect()
  }

  func connect(timeout: TimeInterval = 60) async throws {
    logger.debug("connect")

    state = .connecting
    let connection = NWConnection(to: endpoint, using: newConnectionParameters())
    self.connection = connection
    connection.stateUpdateHandler = { [weak self] state in
      self?.stateDidChange(to: state)
    }

    try await withCheckedThrowingContinuation { continuation in
      self.connectionContinuation = continuation
      connection.start(queue: queue)
    }
  }

  func disconnect() {
    disconnect(throwing: CancellationError())
  }

  private func disconnect(throwing error: Swift.Error) {
    logger.debug("disconnect")

    if state.isConnected {
      connection?.cancel()
      state = .disconnected(closeCode: .normalClosure)
    } else {
      connection?.forceCancel()
    }

    sendContinuation?.resume(throwing: error)
    sendContinuation = nil
    receiveContinuation?.resume(throwing: error)
    receiveContinuation = nil
    connectionContinuation?.resume(throwing: error)
    connectionContinuation = nil
    streamContinuation?.finish(throwing: error)
    streamContinuation = nil
    connection = nil
  }

  func receive(operation: String = #function) async throws -> Data {
    logger.debug("\(operation) -> receive")

    guard let connection = connection, state.isConnected else {
      throw Error.clientError(code: 0, message: "WebSocket is not connected")
    }

    let logger = self.logger
    defer { receiveContinuation = nil }

    return try await withCheckedThrowingContinuation { continuation in
      self.receiveContinuation = continuation

      connection.receiveMessage(completion: { (content, context, isComplete, error) in
        logger.debug("Received message. content: \(String(describing: content)), isComplete: \(isComplete), error: \(String(describing: error))")

        if let error = error {
          continuation.resume(throwing: error)
          return
        }

        content.map { continuation.resume(returning: $0) }
      })
    }
  }

  @available(macOS 14, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  func makeAsyncIterator() -> AsyncIterator {
    stream.makeAsyncIterator()
  }

  func send(_ message: String, operation: String = #function) async throws {
    let data = message.data(using: .utf8)!
    let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
    let context = NWConnection.ContentContext(identifier: "textContext", metadata: [metadata])
    try await send(data, context: context, operation: operation)
  }

  func send(_ message: Data, operation: String = #function) async throws {
    let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
    let context = NWConnection.ContentContext(identifier: "binaryContext", metadata: [metadata])
    try await send(message, context: context, operation: operation)
  }

  private func send(_ message: Data, context: NWConnection.ContentContext, operation: String = #function) async throws {
    logger.debug("\(operation) -> send")

    guard let connection = connection, state.isConnected else {
      throw Error.clientError(code: 0, message: "WebSocket is not connected")
    }

    let logger = self.logger

    defer { sendContinuation = nil }

    try await withCheckedThrowingContinuation { continuation in
      self.sendContinuation = continuation

      connection.send(content: message, contentContext: context, completion: .contentProcessed { error in
        if let error = error {
          logger.error("Send error: \(error)")
          continuation.resume(throwing: error)
        } else {
          logger.debug("Message sent successfully: \(message)")
          continuation.resume()
        }
      })
    }
  }

  private lazy var stream: InternalStream = {
    InternalStream { continuation in
      self.streamContinuation = continuation

      Task {
        var isAlive = true

        while isAlive && self.state.isConnected {
          do {
            let value = try await receive()
            continuation.yield(value)
          } catch {
            continuation.finish(throwing: error)
            self.streamContinuation = nil
            isAlive = false
          }
        }
      }
    }
  }()

  private func newConnectionParameters() -> NWParameters {
    let parameters = url.scheme == "wss" ? NWParameters.tls : NWParameters.tcp
    parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
    return parameters
  }

  private func stateDidChange(to state: NWConnection.State) {
    switch state {
    case .ready:
      logger.debug("Connection ready")
      self.state = .connected()
      connectionContinuation?.resume()
      connectionContinuation = nil
    case .failed(let error):
      logger.error("Connection failed: \(error)")
      self.state = .disconnected(closeCode: .abnormalClosure, closeReason: error.localizedDescription)
      disconnect(throwing: error)
    case .waiting(let error):
      logger.debug("Connection waiting: \(error)")
    case .cancelled:
      logger.debug("Connection cancelled")
      disconnect()
    default:
      break
    }
  }
}
