import Foundation
import UtilityKit
import WebSocketKit

class AirDCConnection {
  private let webSocket: WebSocket
  private let continuations: Continuations = DefaultContinuations()

  init(url: URL) {
    webSocket = WebSocket(url: url)
  }

  public func unauthorizedSend(
    _ content: Data,
    to path: String,
    using method: Message.Method,
    operation: String = #function
  ) async throws -> Data {
    return try await withCheckedThrowingContinuation { continuation in
      let id = continuations.append(continuation)

      let message = Message(
        method: method,
        path: path,
        callbackId: id,
        data: content
      )

      Task {
        do {
          try await webSocket.send(JSONEncoder().encode(message))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func connect() throws {
    Task {
      for try await data in webSocket {
        let message = try JSONDecoder().decode(Message.self, from: data)

        continuations.resumeContinuation(
          withId: message.callbackId,
          returning: message.data
        )
      }
    }
  }
}

extension AirDCConnection {
  struct Message: Codable {
    enum Method: String, Codable {
      case post = "POST"
      case get = "GET"
    }

    let method: Method
    let path: String
    let callbackId: Int
    let data: Data

    enum CodingKeys: String, CodingKey {
      case method
      case path
      case callbackId = "callback_id"
      case data
    }
  }
}
