import Foundation
import Network

class WebSocketServer {
  var port: NWEndpoint.Port? { listener?.port }

  private let shouldUseTLS: Bool
  private let requestedPort: NWEndpoint.Port
  private let requiredInterfaceType: NWInterface.InterfaceType
  private let serverQueue = DispatchQueue(label: "serverQueue")
  private var listener: NWListener?
  private var lastUsedPort: NWEndpoint.Port? = nil
  private var connectedClients: [NWConnection] = []
  private var startContinuation: CheckedContinuation<Void, Swift.Error>?
  private var stopContinuation: CheckedContinuation<Void, Never>?

  init(
    port: NWEndpoint.Port = .any,
    tls: Bool = true,
    requiredInterfaceType: NWInterface.InterfaceType = .other
  ) {
    shouldUseTLS = tls
    self.requestedPort = port
    self.requiredInterfaceType = requiredInterfaceType
  }

  deinit {
    stop(throwing: CancellationError())
  }

  @discardableResult
  func start() async throws -> Self {
    let listener = try NWListener(
      using: newConnectionParameters(),
      on: lastUsedPort ?? requestedPort
    )
    self.listener = listener

    listener.stateUpdateHandler = { [weak self] state in
      self?.stateDidChange(to: state)
    }

    listener.newConnectionHandler = { [weak self] connection in
      self?.clientDidConnect(with: connection)
    }

    listener.start(queue: serverQueue)

    try await withCheckedThrowingContinuation { continuation in
      self.startContinuation = continuation
    }

    return self
  }

  func stop() async {
    await withCheckedContinuation {
      self.stopContinuation = $0
      stop(throwing: CancellationError())
    }
  }

  private func stop(throwing error: Swift.Error) {
    connectedClients.forEach { $0.cancel() }

    startContinuation?.resume(throwing: error)
    startContinuation = nil

    listener?.cancel()
    listener = nil
  }

  private func newConnectionParameters() -> NWParameters {
    let parameters = shouldUseTLS ? NWParameters.tls : NWParameters.tcp
    parameters.requiredInterfaceType = requiredInterfaceType

    let wsOptions = NWProtocolWebSocket.Options()
    wsOptions.autoReplyPing = true

    parameters.defaultProtocolStack.applicationProtocols.insert(
      wsOptions,
      at: 0
    )

    return parameters
  }

  private func clientDidConnect(with connection: NWConnection) {
    connectedClients.append(connection)

    connection.stateUpdateHandler = { [weak self] state in
      self?.connectionStateDidChange(to: state, for: connection)
    }

    connection.start(queue: serverQueue)

    func receive() {
      connection.receiveMessage {
        [weak self] (data, context, isComplete, error) in
        if let data = data, let context = context {
          self?.handleMessage(data: data, in: context, for: connection)
          receive()
        }
      }
    }

    receive()
  }

  private func handleMessage(
    data: Data,
    in context: NWConnection.ContentContext,
    for connection: NWConnection
  ) {
    let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
    let context = NWConnection.ContentContext(
      identifier: "binaryContext",
      metadata: [metadata]
    )

    connection.send(
      content: data,
      contentContext: context,
      isComplete: true,
      completion: .contentProcessed({ _ in })
    )
  }

  private func stateDidChange(to state: NWListener.State) {
    switch state {
    case .ready:
      startContinuation?.resume()
      startContinuation = nil
      lastUsedPort = port
    case .failed(let error):
      stop(throwing: error)
    case .cancelled:
      stopContinuation?.resume()
      stopContinuation = nil
    default:
      break
    }
  }

  func connectionStateDidChange(
    to state: NWConnection.State,
    for connection: NWConnection
  ) {
    switch state {
    case .failed:
      connection.cancel()
      connectedClients.remove(connection)
    case .cancelled:
      connectedClients.remove(connection)
    default:
      break
    }
  }
}

extension NWConnection: @retroactive Equatable {
  public static func == (lhs: NWConnection, rhs: NWConnection) -> Bool {
    return lhs === rhs
  }
}

extension Array where Element: Equatable {
  @discardableResult mutating func remove(_ element: Element) -> Element? {
    if let index = firstIndex(of: element) {
      return remove(at: index)
    }
    return nil
  }
}
