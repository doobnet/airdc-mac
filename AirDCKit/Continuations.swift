import Foundation

typealias Continuation = CheckedContinuation<Foundation.Data, Error>

class Continuations {
    typealias ID = Int
    private var continuations: [ID: Continuation] = [:]
    private let maxId = ID(Int32.max)
    private let logger = Logging.newLogger()

    func append(_ continuation: Continuation) -> ID {
        let maxTries = 10

        for _ in 0 ..< maxTries {
            let id = Int.random(in: 0 ..< maxId)
            guard continuations[id] == nil else { continue }

            continuations[id] = continuation
            return id
        }

        fatalError("Failed to generate unsued continuation ID after \(maxTries) tries")
    }

    func resumeContinuation(withId id: ID, returning data: Data) -> Bool {
        guard let continuation = continuations[id] else { return false }
        logger.debug("resuming continuation with id: \(id)")
        continuation.resume(returning: data)
        return true
    }

    func resumeContinuation(withId id: ID, throwing error: Error) -> Bool {
        guard let continuation = continuations[id] else { return false }
        logger.debug("throwing continuation with id: \(id)")
        continuation.resume(throwing: error)
        return true
    }
}
