import Foundation
import Network

class WebSocketServer {
  static var shared = WebSocketServer()
  var listener: NWListener?
  var connectedClients: [NWConnection] = []
  let shouldUseTLS: Bool
  let requestedPort: NWEndpoint.Port

  var port: NWEndpoint.Port? { listener?.port }

  init(port: NWEndpoint.Port = .any, tls: Bool = true) {
    shouldUseTLS = tls
    self.requestedPort = port
    //configureLocalIdentity(on: tlsOptions)

  }

  func start() throws {

    let listener = try NWListener(
      using: newConnectionParameters(),
      on: requestedPort
    )
    self.listener = listener
    let serverQueue = DispatchQueue(label: "serverQueue")

    listener.newConnectionHandler = { newConnection in
      self.connectedClients.append(newConnection)
      newConnection.start(queue: serverQueue)

      func receive() {
        newConnection.receiveMessage { (data, context, isComplete, error) in
          if let data = data, let context = context {
            self.handleMessage(data: data, context: context)
            receive()
          }
        }
      }

      receive()
    }

    listener.start(queue: serverQueue)

  }

  private func newConnectionParameters() -> NWParameters {
    let parameters = shouldUseTLS ? NWParameters.tls : NWParameters.tcp
    let wsOptions = NWProtocolWebSocket.Options()
    wsOptions.autoReplyPing = true
    parameters.defaultProtocolStack.applicationProtocols.insert(
      wsOptions,
      at: 0
    )
    return parameters
  }

  func handleMessage(data: Data, context: NWConnection.ContentContext) {
    print("Received message: \(context)")
    let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
    let context = NWConnection.ContentContext(
      identifier: "binaryContext",
      metadata: [metadata]
    )

    for client in connectedClients {
      client.send(
        content: data,
        contentContext: context,
        isComplete: true,
        completion: .contentProcessed({ _ in })
      )
    }
  }
}
