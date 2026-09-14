import Foundation
import Testing

@testable import AirDCKit

struct AuthorizeMessage: Codable {
  let username: String
  let password: String
}

struct AirDCConnectionTests {
  let url = URL(string: "wss://nas:5601/api/v1")!

  @Test("unauthorizedSend", .disabled("requires a live AirDC++ server"))
  func unauthorizedSend() async throws {
    let connection = AirDCConnection(url: url)
    try connection.connect()
    let data = try JSONEncoder().encode(
      AuthorizeMessage(username: "foo", password: "bar")
    )
    let result = try await connection.unauthorizedSend(
      data,
      to: "/session/authorize",
      using:
        AirDCConnection.Message.Method.post
    )

    print(result)
  }
}
