import Foundation

typealias InternalStream = AsyncThrowingStream<
    URLSessionWebSocketTask.Message, Error
>

@available(macOS 14, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
class WebSocketSequence: AsyncSequence {
    typealias AsyncIterator = InternalStream.Iterator
    typealias Element = URLSessionWebSocketTask.Message

    private var continuation: InternalStream.Continuation?
    private let task: URLSessionWebSocketTask

    private lazy var stream: InternalStream = {
        InternalStream { continuation in
            self.continuation = continuation

            Task {
                var isAlive = true

                while isAlive && task.closeCode == .invalid {
                    do {
                        let value = try await task.receive()
                        continuation.yield(value)
                    } catch {
                        continuation.finish(throwing: error)
                        isAlive = false
                    }
                }
            }
        }
    }()

    init(task: URLSessionWebSocketTask) {
        self.task = task
        task.resume()
    }

    deinit {
        continuation?.finish()
    }

    func makeAsyncIterator() -> InternalStream.Iterator {
        stream.makeAsyncIterator()
    }

    func cancel() async throws {
        task.cancel(with: .goingAway, reason: nil)
        continuation?.finish()
    }
}
