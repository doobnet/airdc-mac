import Foundation
import Network
import OSLog
import UtilityKit

typealias InternalStream = AsyncThrowingStream<Data, Error>

class WebSocket: AsyncSequence {
  struct AutoReconnect {
    let enabled: Bool
    let maxRetries: Int
    let delay: Duration

    init(enabled: Bool = false, maxRetries: Int = 5, delay: Duration = .seconds(10)) {
      self.enabled = enabled
      self.maxRetries = maxRetries
      self.delay = delay
    }
  }

  typealias AsyncIterator = InternalStream.Iterator
  typealias Element = InternalStream.Element
  typealias State = NWConnection.State
  typealias StateUpdateHandler = @Sendable (_ state: State) -> Void

  enum Error: Swift.Error {
    case notConnected
    case timeout
  }

  var stateUpdateHandler: StateUpdateHandler = { _ in }

  private let logger: Logger
  private let url: URL
  private let endpoint: NWEndpoint
  private var streamContinuation: InternalStream.Continuation?
  private var receiveContinuation: CheckedContinuation<Data, Swift.Error>?
  private var connectionContinuation: CheckedContinuation<Void, Swift.Error>?
  private var connection: NWConnection?
  private let queue = DispatchQueue(label: "WebSocketQueue")
  private let autoReconnect: AutoReconnect

  init(url: URL, logger: Logger = Logging.newLogger(), autoReconnect: AutoReconnect = AutoReconnect()) {
    self.logger = logger
    self.url = url
    self.endpoint = NWEndpoint.url(url)
    self.autoReconnect = autoReconnect
  }

  deinit {
    disconnect()
  }

  var state: State {
    connection?.state ?? .setup
  }

  @discardableResult
  func connect(timeout: TimeInterval = 60) async throws -> Self {
    logger.debug("connect")

    let connection = NWConnection(
      to: endpoint,
      using: newConnectionParameters()
    )
    self.connection = connection
    connection.stateUpdateHandler = { [weak self] state in
      self?.stateDidChange(to: state)
    }

    try await withCheckedThrowingContinuation { continuation in
      self.connectionContinuation = continuation
      connection.start(queue: queue)
    }

    return self
  }

  func disconnect() {
    disconnect(throwing: CancellationError())
  }

  private func disconnect(throwing error: Swift.Error) {
    logger.debug("disconnect")

    if state.isConnected {
      connection?.cancel()
    } else {
      connection?.forceCancel()
    }

    receiveContinuation?.resume(throwing: error)
    receiveContinuation = nil
    connectionContinuation?.resume(throwing: error)
    connectionContinuation = nil
    streamContinuation?.finish(throwing: error)
    streamContinuation = nil
    connection = nil
  }

  func receive(operation: String = #function) async throws -> Data {
    try await withRetry {
      try await receiveWihtoutRetry(operation: operation)
    }
  }

  private func receiveWihtoutRetry(operation: String = #function) async throws -> Data {
    logger.debug("\(operation) -> receive")

    guard let connection = connection, state.isConnected else {
      throw Error.notConnected
    }

    let logger = self.logger
    defer { receiveContinuation = nil }

    return try await withCheckedThrowingContinuation { continuation in
      self.receiveContinuation = continuation

      connection.receiveMessage(completion: {
        (content, context, isComplete, error) in
        logger.debug(
          "Received message. content: \(String(describing: content)), isComplete: \(isComplete), error: \(String(describing: error))"
        )

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

  @discardableResult @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, *)
  func send(_ message: String, operation: String = #function) async throws -> Self {
    let data = message.data(using: .utf8)!
    let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
    let context = NWConnection.ContentContext(
      identifier: "textContext",
      metadata: [metadata]
    )

    try await withRetry {
      try await send(data, context: context, operation: operation)
    }

    return self
  }

  @discardableResult
  func send(_ message: Data, operation: String = #function) async throws -> Self {
    let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
    let context = NWConnection.ContentContext(
      identifier: "binaryContext",
      metadata: [metadata]
    )

    try await withRetry {
      try await send(message, context: context, operation: operation)
    }

    return self
  }

  private func send(
    _ message: Data,
    context: NWConnection.ContentContext,
    operation: String = #function
  ) async throws {
    logger.debug("\(operation) -> send")

    guard let connection = connection, state.isConnected else {
      throw Error.notConnected
    }

    let logger = self.logger

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
      connection.send(
        content: message,
        contentContext: context,
        completion: .contentProcessed { error in
          if let error = error {
            logger.error("Send error: \(error)")
            continuation.resume(throwing: error)
          } else {
            logger.debug("Message sent successfully: \(message)")
            continuation.resume()
          }
        }
      )
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
    parameters.defaultProtocolStack.applicationProtocols.insert(
      NWProtocolWebSocket.Options(),
      at: 0
    )
    return parameters
  }

  private func withRetry<R>(operation: () async throws -> R) async throws -> R {
    guard autoReconnect.enabled else { return try await operation() }

    var lastError: Swift.Error?

    for attempt in 0..<self.autoReconnect.maxRetries {
      do {
        return try await operation()
      } catch {
        lastError = error
        logger.debug("Reconnection attempt \(attempt + 1) failed: \(error)")
      }

      try? await Task.sleep(for: autoReconnect.delay)
      try await connect()
    }

    throw lastError!
  }

  private func stateDidChange(to state: NWConnection.State) {
    switch state {
    case .ready:
      logger.debug("Connection ready")
      connectionContinuation?.resume()
      connectionContinuation = nil
    case .failed(let error):
      logger.error("Connection failed: \(error)")
      disconnect(throwing: error)
    case .cancelled:
      logger.debug("Connection cancelled")
      disconnect()
    default:
      break
    }

    stateUpdateHandler(state)
  }
}

extension WebSocket.State {
  var isConnected: Bool { self == .ready }
}
