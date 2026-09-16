import Foundation
import UtilityKit
import WebSocketKit

public final class AirDCConnection {
  /// The HTTP-style verb an AirDC++ API request is issued with.
  public enum Method: String, Codable {
    case post = "POST"
    case get = "GET"
  }

  private let webSocket: WebSocketKit.WebSocket
  private let continuations: Continuations

  public convenience init(url: URL) {
    self.init(webSocket: WebSocketKit.WebSocket(url: url))
  }

  init(
    webSocket: WebSocketKit.WebSocket,
    continuations: Continuations = DefaultContinuations()
  ) {
    self.webSocket = webSocket
    self.continuations = continuations
  }

  public func unauthorizedSend(
    _ content: Data,
    to path: String,
    using method: Method,
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
  /// The wire envelope AirDC++ wraps every request and response in.
  struct Message: Codable {
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
