import Foundation
import Testing

@testable import AirDCKit

struct AirDCKitTests {
  let data = "data".data(using: .utf8)!
  let continuations = DefaultContinuations()

  @Test("resume continuation by returning")
  func resumeContinuationReturning() async throws {
    let result = try await withCheckedThrowingContinuation {
      let id = continuations.append($0)
      let _ = continuations.resumeContinuation(withId: id, returning: data)
    }

    #expect(result == data)
  }

  @Test("resume continuation by returning with unknown id")
  func resumeContinuationReturningWithUnkownId() async throws {
    let _ = try await withCheckedThrowingContinuation {
      let id = continuations.append($0)

      let found = continuations.resumeContinuation(
        withId: unknownId(id),
        returning: data
      )

      #expect(!found)

      continuations.resumeAll(with: data)
    }
  }

  @Test("resume continuation by throwing")
  func resumeContinuationThrowing() async throws {
    struct Error: Swift.Error {}

    await #expect(throws: Error.self) {
      let _ = try await withCheckedThrowingContinuation {
        let id = continuations.append($0)
        let _ = continuations.resumeContinuation(withId: id, throwing: Error())
      }
    }
  }

  func unknownId(_ id: Continuations.ID) -> Continuations.ID {
    id == Continuations.ID.max ? id - 1 : id + 1
  }
}
