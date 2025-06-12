import Foundation

import SwiftMock

typealias InternalStreamElement = URLSessionWebSocketTask.Message
typealias InternalStream = AsyncThrowingStream<InternalStreamElement, Error>

@Mock protocol Continuable {
    func finish()
    func finish(throwing error: Error?)

    @discardableResult
    func yield(_ value: InternalStreamElement) -> InternalStream.Continuation.YieldResult
}

extension InternalStream.Continuation: Continuable {
    func finish() {
        finish(throwing: nil)
    }
}

class WebSocketSequence: AsyncSequence {
    typealias AsyncIterator = InternalStream.Iterator
    typealias Element = URLSessionWebSocketTask.Message

    private var continuation: Continuable?
    private let task: Transport

    private lazy var stream: InternalStream = InternalStream { continuation in
        self.continuation = continuation
        waitForNextValue()
    }

    init(task: Transport, continuation: Continuable? = nil) {
        self.task = task
        self.continuation = continuation
        task.resume()
    }

    deinit {
        continuation?.finish()
    }

    func makeAsyncIterator() -> AsyncIterator {
        return stream.makeAsyncIterator()
    }

    func cancel() async throws {
        task.cancel(with: .goingAway, reason: nil)
        continuation?.finish()
    }

    private func waitForNextValue() {
        guard task.closeCode == .invalid else {
            continuation?.finish()
            return
        }

        task.receive(completionHandler: { [weak self] result in
            guard let continuation = self?.continuation else { return }

            do {
                let message = try result.get()
                continuation.yield(message)
                self?.waitForNextValue()
            } catch {
                continuation.finish(throwing: error)
            }
        })
    }
}
