import Foundation
import OSLog
import UtilityKit
import WebSocketKit

public final class AirDCConnection {
  /// The HTTP-style verb an AirDC++ API request is issued with.
  public enum Method: String, Codable {
    case post = "POST"
    case get = "GET"
  }

  /// A request that reached the server and came back rejected.
  public enum Error: Swift.Error {
    case clientError(code: Int, message: String)
    case serverError(code: Int, message: String)
  }

  private let webSocket: WebSocketKit.WebSocket
  private let continuations: Continuations
  private let logger: Logger
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public convenience init(url: URL) {
    self.init(webSocket: WebSocketKit.WebSocket(url: url))
  }

  init(
    webSocket: WebSocketKit.WebSocket,
    continuations: Continuations = DefaultContinuations(),
    logger: Logger = Logging.newLogger()
  ) {
    self.webSocket = webSocket
    self.continuations = continuations
    self.logger = logger
  }

  /// Sends `payload` without an authorization token and waits for the reply
  /// that carries the matching callback ID.
  ///
  /// - Returns: The raw reply envelope. Decode it as
  ///   ``AirDCConnection/Response`` for the endpoint's payload type.
  public func unauthorizedSend<Payload: Encodable>(
    _ payload: Payload,
    to path: String,
    using method: Method,
    operation: String = #function
  ) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      let id = continuations.append(continuation)
      logger.debug("\(operation) -> \(method.rawValue) \(path), id: \(id)")

      send(
        Request(method: method, path: path, callbackId: id, data: payload),
        waitingOn: id
      )
    }
  }

  /// Encodes and delivers `request`, handing a send failure back to the
  /// caller waiting on `id` rather than losing it.
  private func send<Payload: Encodable>(
    _ request: Request<Payload>,
    waitingOn id: Continuations.ID
  ) {
    Task {
      do {
        try await webSocket.send(encoder.encode(request))
      } catch {
        continuations.resumeContinuation(withId: id, throwing: error)
      }
    }
  }

  public func connect() throws {
    Task {
      for try await data in webSocket {
        route(data)
      }
    }
  }

  /// Hands a reply to whichever caller is waiting on its callback ID.
  ///
  /// A reply that cannot be decoded is logged and dropped rather than thrown,
  /// so one malformed message does not tear down the connection and strand
  /// every pending request.
  private func route(_ data: Data) {
    guard
      let header = try? decoder.decode(ResponseHeader.self, from: data)
    else {
      logger.error("Discarding undecodable reply of \(data.count) bytes")
      return
    }

    let resumed = continuations.resumeContinuation(
      withId: header.callbackId,
      with: header.result(carrying: data).mapError { $0 as Swift.Error }
    )

    if !resumed {
      logger.debug("Reply not initiated by client, id: \(header.callbackId)")
    }
  }
}
