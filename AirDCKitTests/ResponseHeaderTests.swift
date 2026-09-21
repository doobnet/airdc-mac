import Foundation
import Testing

@testable import AirDCKit

struct ResponseHeaderTests {
  typealias Header = AirDCConnection.ResponseHeader

  let body = Data("body".utf8)
  let decoder = JSONDecoder()

  func header(code: Int, message: String? = nil) throws -> Header {
    let error = message.map { #","error":{"message":"\#($0)"}"# } ?? ""
    let json = #"{"code":\#(code),"callback_id":7\#(error)}"#

    return try decoder.decode(Header.self, from: Data(json.utf8))
  }

  @Test("decodes a reply without a data field")
  func decodesWithoutData() throws {
    let header = try header(code: 200)

    #expect(header.code == 200)
    #expect(header.callbackId == 7)
    #expect(header.error == nil)
  }

  @Test(
    "treats 2xx and 3xx as success, carrying the body",
    arguments: [200, 201, 204, 302, 399]
  )
  func successCarriesBody(code: Int) throws {
    let result = try header(code: code).result(carrying: body)

    #expect(try result.get() == body)
  }

  @Test("reports 4xx as a client error", arguments: [400, 401, 404, 499])
  func clientError(code: Int) throws {
    let result = try header(code: code, message: "nope").result(carrying: body)

    guard case .failure(.clientError(let actual, let message)) = result else {
      Issue.record("Expected a client error, got \(result)")
      return
    }

    #expect(actual == code)
    #expect(message == "nope")
  }

  @Test("reports 5xx as a server error", arguments: [500, 503, 599])
  func serverError(code: Int) throws {
    let result = try header(code: code, message: "boom").result(carrying: body)

    guard case .failure(.serverError(let actual, let message)) = result else {
      Issue.record("Expected a server error, got \(result)")
      return
    }

    #expect(actual == code)
    #expect(message == "boom")
  }

  @Test(
    "reports codes outside the known ranges as a server error",
    arguments: [0, 100, 600, 999]
  )
  func unknownCode(code: Int) throws {
    let result = try header(code: code, message: "weird").result(carrying: body)

    guard case .failure(.serverError(let actual, _)) = result else {
      Issue.record("Expected a server error, got \(result)")
      return
    }

    #expect(actual == code)
  }

  @Test("substitutes a message when the failure omits one")
  func missingMessage() throws {
    let result = try header(code: 500).result(carrying: body)

    guard case .failure(.serverError(_, let message)) = result else {
      Issue.record("Expected a server error, got \(result)")
      return
    }

    #expect(message == "No message provided")
  }
}
