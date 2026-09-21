import Foundation
import OSLog
import Synchronization
import UtilityKit

typealias Continuation = CheckedContinuation<Foundation.Data, Error>

protocol Continuations {
  typealias ID = Int

  func append(_ continuation: Continuation) -> ID

  @discardableResult
  func resumeContinuation(withId id: ID, with result: Result<Data, Error>)
    -> Bool
}

extension Continuations {
  @discardableResult
  func resumeContinuation(withId id: ID, returning data: Data) -> Bool {
    resumeContinuation(withId: id, with: .success(data))
  }

  @discardableResult
  func resumeContinuation(withId id: ID, throwing error: Error) -> Bool {
    resumeContinuation(withId: id, with: .failure(error))
  }
}

final class DefaultContinuations: Continuations {
  private let continuations = Mutex<[ID: Continuation]>([:])
  private let maxId = ID(Int32.max)
  private let logger = Logging.newLogger()

  func resumeAll(with data: Data) {
    let pending = continuations.withLock {
      let values = Array($0.values)
      $0.removeAll()
      return values
    }

    for continuation in pending {
      continuation.resume(returning: data)
    }
  }

  func append(_ continuation: Continuation) -> ID {
    let maxTries = 10

    for _ in 0..<maxTries {
      let id = Int.random(in: 0..<maxId)

      let inserted = continuations.withLock {
        guard $0[id] == nil else { return false }
        $0[id] = continuation
        return true
      }

      if inserted { return id }
    }

    fatalError(
      "Failed to generate unsued continuation ID after \(maxTries) tries"
    )
  }

  @discardableResult
  func resumeContinuation(withId id: ID, with result: Result<Data, Error>)
    -> Bool
  {
    guard let continuation = remove(id) else { return false }

    logger.debug("resuming continuation with id: \(id)")
    continuation.resume(with: result)

    return true
  }

  private func remove(_ id: ID) -> Continuation? {
    continuations.withLock { $0.removeValue(forKey: id) }
  }
}
