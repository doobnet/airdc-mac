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

    let result = try await connection.unauthorizedSend(
      AuthorizeMessage(username: "foo", password: "bar"),
      to: "/session/authorize",
      using: .post
    )

    print(result)
  }
}
