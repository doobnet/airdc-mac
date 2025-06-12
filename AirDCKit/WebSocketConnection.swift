import Foundation

// protocol Session {
//    func webSocketTask(with request: URLRequest) -> Transport
// }

public protocol Transport {
    func resume() -> Void
    func receive() async throws -> URLSessionWebSocketTask.Message
    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping (Error?) -> Void)
}

class WebSocketConnection {
    enum Error: Swift.Error {
        case clientError(code: Int, message: String)
        case serverError(code: Int, message: String)
    }

    private struct Response<Data: Codable>: Codable {
        let data: Data
    }

    private var continuations: Continuations = .init()
    private var authorizationToken: String?

    private let socket: Transport

    private lazy var encoder = tap(JSONEncoder()) {
        $0.keyEncodingStrategy = .convertToSnakeCase
    }

    private lazy var decoder = tap(JSONDecoder()) {
        $0.keyDecodingStrategy = .convertFromSnakeCase
    }

    init(transport: Transport) {
        socket = transport
    }

    func connect() throws {
        print("connect")
        socket.resume()

        Task {
            while true {
                do {
                    switch try await socket.receive() {
                    case .data(let data):
                        try handleMessage(data)
                    case .string(let text):
                        try handleMessage(Data(text.utf8))
                    @unknown default:
                        fatalError("Unhandled case for receiving from web socket")
                    }
                } catch {
                    print("Handle error: \(error)")
                }
            }
        }
    }

    func send<Data: Codable>(_ message: Data, to path: String, using method: Method, operation: String = #function) async throws -> Foundation.Data {
        return try await withCheckedThrowingContinuation { continuation in
            let id = continuations.append(continuation)
            let socketMessage = WebSocketMessage<Data>(
                method: method, path: path, callbackId: id, data: message
            )

            print("sending message: \(operation) with ID: \(id)")

            try! socket.send(encode(socketMessage)) {
                if let error = $0 {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func handleMessage(_ data: Data) throws {
        struct Response: Codable {
            struct Error: Codable {
                var message: String
            }

            var code: Int
            var callback_id: Int
            var error: Error?
        }

        print("Received message: \(String(decoding: data, as: UTF8.self))")

        let message = try decoder.decode(Response.self, from: data)

        func resume(throwing partialError: (Int, String) -> Error) -> Bool {
            let error = partialError(message.code, message.error?.message ?? "")
            return continuations.resumeContinuation(withId: message.callback_id, throwing: error)
        }

        let resumed = switch message.code {
        case 200 ..< 400:
            continuations.resumeContinuation(withId: message.callback_id, returning: data)
        case 400 ..< 500:
            resume(throwing: Error.clientError)
        case 500 ..< 600:
            resume(throwing: Error.serverError)
        default:
            fatalError("Unhandled response code: \(message.code)")
        }

        if resumed == false { print("Message not initiated by client") }
    }

    private func encode<Data: Encodable>(_ message: WebSocketMessage<Data>) throws -> URLSessionWebSocketTask.Message {
        try URLSessionWebSocketTask.Message.data(encoder.encode(message))
    }

    private func decode<Data: Codable>(_ type: Data.Type, from data: Foundation.Data) throws -> Data {
        try decoder.decode(Response<Data>.self, from: data).data
    }
}

private func tap<T>(_ value: T, operation: (_: T) -> Void) -> T {
    operation(value)
    return value
}
