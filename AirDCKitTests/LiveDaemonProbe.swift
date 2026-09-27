// Throwaway probe for "Do the new frameworks reproduce the proven
// connect-and-authorize path?" (#2). Kept on this branch as evidence; skipped
// unless AIRDC_PROBE_USERNAME and AIRDC_PROBE_PASSWORD are set (pass them as
// TEST_RUNNER_AIRDC_PROBE_* to xcodebuild).

import Foundation
import Testing

@testable import AirDCKit
@testable import WebSocketKit

struct ProbeCredentials: Encodable {
  let username: String
  let password: String
}

struct ProbeToken: Decodable {
  let auth_token: String
}

struct ProbeHub: Decodable {
  let name: String
}

struct ProbeTokenMessage: Encodable {
  let auth_token: String
}

struct ProbeEmpty: Encodable {}

struct ProbeTimeout: Error {}

func withTimeout<T: Sendable>(
  _ seconds: Int,
  _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  // Races without awaiting the loser: a stuck continuation ignores cancellation.
  let (stream, continuation) = AsyncThrowingStream<T, Error>.makeStream()
  let work = Task {
    do {
      continuation.yield(try await operation())
      continuation.finish()
    } catch {
      continuation.finish(throwing: error)
    }
  }
  let timer = Task {
    try? await Task.sleep(for: .seconds(seconds))
    continuation.finish(throwing: ProbeTimeout())
  }
  defer {
    work.cancel()
    timer.cancel()
  }
  for try await value in stream { return value }
  throw ProbeTimeout()
}

func probeLog(_ line: String) {
  let path = FileManager.default.temporaryDirectory.appending(path: "probe-events.log").path
  let data = Data("\(Date()) \(line)\n".utf8)
  if let handle = FileHandle(forWritingAtPath: path) {
    handle.seekToEndOfFile()
    handle.write(data)
    try? handle.close()
  } else {
    FileManager.default.createFile(atPath: path, contents: data)
  }
}

@Suite(.serialized, .timeLimit(.minutes(1)), .enabled(if: ProcessInfo.processInfo.environment["AIRDC_PROBE_PASSWORD"] != nil))
struct LiveDaemonProbe {
  let env = ProcessInfo.processInfo.environment
  var host: String { env["AIRDC_PROBE_HOST"] ?? "nas" }
  var url: URL { URL(string: "wss://\(host):5601/api/v1/")! }
  var credentials: ProbeCredentials {
    ProbeCredentials(username: env["AIRDC_PROBE_USERNAME"]!, password: env["AIRDC_PROBE_PASSWORD"]!)
  }

  func log(_ s: String) { probeLog(s) }

  func authorize(_ connection: AirDCConnection) async throws -> String {
    let creds = credentials
    let data = try await withTimeout(15) {
      try await connection.unauthorizedSend(creds, to: "/sessions/authorize", using: .post)
    }
    return try JSONDecoder().decode(AirDCConnection.Response<ProbeToken>.self, from: data).data.auth_token
  }

  func favoriteHubs(_ connection: AirDCConnection, token: String?) async throws -> [String] {
    let data: Data
    if let token {
      data = try await withTimeout(15) {
        try await connection.unauthorizedSend(ProbeTokenMessage(auth_token: token), to: "/favorite_hubs/0/100", using: .get)
      }
    } else {
      data = try await withTimeout(15) {
        try await connection.unauthorizedSend(ProbeEmpty(), to: "/favorite_hubs/0/100", using: .get)
      }
    }
    return try JSONDecoder().decode(AirDCConnection.Response<[ProbeHub]>.self, from: data).data.map(\.name)
  }

  @Test("A: public init, system trust")
  func publicInit() async throws {
    let webSocket = WebSocket(url: url)
    webSocket.stateUpdateHandler = { probeLog("A state \($0)") }
    let connection = AirDCConnection(webSocket: webSocket)
    try connection.connect()
    do {
      _ = try await authorize(connection)
      log("A: authorized")
    } catch {
      log("A: failed: \(error)")
    }
  }

  @Test("B: trusting NAS, connect before first send")
  func trustingConnectFirst() async throws {
    let webSocket = WebSocket(url: url, certificateValidation: .trustingAnyCertificate(from: host))
    webSocket.stateUpdateHandler = { probeLog("B state \($0)") }
    let connection = AirDCConnection(webSocket: webSocket)
    try connection.connect()
    do {
      let token = try await authorize(connection)
      log("B: authorized, token length \(token.count)")
      let hubs = try await favoriteHubs(connection, token: token)
      log("B: favorite hubs with token: \(hubs.count)")
    } catch {
      log("B: failed: \(error)")
    }
  }

  @Test("C: trusting NAS, open socket before connect()")
  func trustingOpenFirst() async throws {
    let webSocket = WebSocket(url: url, certificateValidation: .trustingAnyCertificate(from: host))
    let connection = AirDCConnection(webSocket: webSocket)
    // Force the NetworkConnection to start and reach .ready before
    // AirDCConnection starts iterating the socket.
    let creds = credentials
    do {
      try await withTimeout(15) { _ = try await webSocket.send(JSONEncoder().encode(
        AirDCConnection.Request(method: .post, path: "/sessions/authorize", callbackId: 1, data: creds))) }
      log("C: state after raw send: \(webSocket.state)")
      let raw = try await withTimeout(15) { try await webSocket.receive() }
      let token = try JSONDecoder().decode(AirDCConnection.Response<ProbeToken>.self, from: raw).data.auth_token
      log("C: authorized via raw socket, token length \(token.count)")
      try connection.connect()
      let withToken = try await favoriteHubs(connection, token: token)
      log("C: favorite hubs with token: \(withToken.count)")
      let withoutToken = try await favoriteHubs(connection, token: nil)
      log("C: favorite hubs without token: \(withoutToken.count)")
    } catch {
      log("C: failed: \(error)")
    }
  }
}
