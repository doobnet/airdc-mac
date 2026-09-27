import Foundation

/// Raw, read/write JSON access to a Daemon's HTTP API with Basic auth.
/// Deliberately independent of `AirDCKit`: this proof is about the Daemons.
struct DaemonHTTP: Sendable {
  let port: Int
  let username: String
  let password: String

  func get(_ path: String) async throws -> Any {
    try await send("GET", path, body: nil)
  }

  func post(_ path: String, _ body: [String: Any]) async throws -> Any {
    try await send("POST", path, body: body)
  }

  private func send(_ method: String, _ path: String, body: [String: Any]?) async throws -> Any {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/v1/\(path)")!)
    request.httpMethod = method
    request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try body.map { try JSONSerialization.data(withJSONObject: $0) }

    let (data, response) = try await URLSession.shared.data(for: request)
    try check(response, data: data, request: "\(method) \(path)")
    return data.isEmpty ? [:] : try JSONSerialization.jsonObject(with: data)
  }

  private var credentials: String {
    Data("\(username):\(password)".utf8).base64EncodedString()
  }

  private func check(_ response: URLResponse, data: Data, request: String) throws {
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      throw Failure(description: "\(request) -> \(status): \(String(decoding: data, as: UTF8.self))")
    }
  }

  struct Failure: Error, CustomStringConvertible {
    let description: String
  }
}
