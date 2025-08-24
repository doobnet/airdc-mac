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

    init(
      enabled: Bool = false,
      maxRetries: Int = 5,
      delay: Duration = .seconds(10)
    ) {
      self.enabled = enabled
      self.maxRetries = maxRetries
      self.delay = delay
    }
  }

  typealias AsyncIterator = InternalStream.Iterator
  typealias Element = InternalStream.Element
  typealias Connection = NetworkConnection<Network.WebSocket>
  typealias State = Connection.State
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
  private var connection: NetworkConnection<Network.WebSocket>?
  private let queue = DispatchQueue(label: "WebSocketQueue")
  private let autoReconnect: AutoReconnect

  init(
    url: URL,
    logger: Logger = Logging.newLogger(),
    autoReconnect: AutoReconnect = AutoReconnect()
  ) {
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

  private var messageProtocol: Network.WebSocket {
    let messageProtocol = if url.scheme == "wss" {
      Network.WebSocket { TLS() }
    } else {
      Network.WebSocket { TCP() }
    }

    return messageProtocol.autoReplyPing(true)
  }

  @discardableResult
  func connect(timeout: TimeInterval = 60) async throws -> Self {
    logger.debug("connect")

    self.connection = NetworkConnection(to: endpoint) {
      messageProtocol
    }
    .onStateUpdate { [weak self] in self?.stateDidChange(to: $1) }

    return self
  }

  func disconnect() {
    disconnect(throwing: CancellationError())
  }

  private func disconnect(throwing error: Swift.Error) {
    logger.debug("disconnect")

    streamContinuation?.finish(throwing: error)
    streamContinuation = nil
    connection = nil
  }

  func receive(operation: String = #function) async throws -> Data {
    try await withRetry {
      try await receiveWihtoutRetry(operation: operation)
    }
  }

  private func receiveWihtoutRetry(operation: String = #function) async throws
    -> Data
  {
    logger.debug("\(operation) -> receive")

    guard let connection = connection else {
      throw Error.notConnected
    }

    let (content, metadata) = try await connection.receive()

    logger.debug(
      "Received message. content: \(String(describing: content)), isComplete: \(metadata.isComplete)"
    )

    return content

  }

  @available(macOS 14, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  func makeAsyncIterator() -> AsyncIterator {
    stream.makeAsyncIterator()
  }

  @discardableResult
  @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, *)
  func send(_ message: String, operation: String = #function) async throws
    -> Self
  {
    guard let connection = connection else {
      throw Error.notConnected
    }

    try await withRetry {
      try await connection.send(message)
    }

    logger.debug("Message sent successfully: \(message)")

    return self
  }

  @discardableResult
  func send(_ message: Data, operation: String = #function) async throws -> Self
  {
    guard let connection = connection else {
      throw Error.notConnected
    }

    try await withRetry {
      try await connection.send(message)
    }

    logger.debug("Message sent successfully: \(message)")

    return self
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

  private func stateDidChange(to state: State) {
    switch state {
    case .ready:
      logger.debug("Connection ready")
    case .failed(let error):
      logger.error("Connection failed: \(error)")
      disconnect(throwing: error)
    case .cancelled:
      logger.debug("Connection cancelled")
      disconnect()
    case .preparing:
      logger.debug("Connection preparing...")
    case .setup:
      logger.debug("Connection setup...")
    case .waiting(let error):
      logger.debug("Connection waiting: \(error)")
    default:
      logger.debug("Connection state changed: ...")
    }

    stateUpdateHandler(state)
  }
}

extension WebSocket.State {
  var isConnected: Bool { self == .ready }
}
