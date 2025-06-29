import AirDCKit
import SwiftUI

enum Method: String, Codable {
    case post = "POST"
    case get = "GET"
}

struct WebSocketMessage<Data: Codable>: Codable {
    var method: Method
    var path: String
    var callback_id: Int
    var data: Data
}

struct AuthenticationMessage: Codable {
    var username: String
    var password: String
}

struct Hub: Codable {
    var name: String
}

typealias Continuation = CheckedContinuation<Foundation.Data, Error>

class Continuations {
    typealias ID = Int
    private var continuations: [ID: Continuation] = [:]
    private let maxId = ID(Int32.max)

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
        print("resuming continuation: \(continuation) with id: \(id)")
        continuation.resume(returning: data)
        return true
    }

    func resumeContinuation(withId id: ID, throwing error: Error) -> Bool {
        guard let continuation = continuations[id] else { return false }
        print("throwing continuation: \(continuation) with id: \(id)")
        continuation.resume(throwing: error)
        return true
    }
}

struct Response<Data: Codable>: Codable {
    var data: Data
}

struct Authenticate: Codable {
    var auth_token: String
}

protocol AuthorizationToken: Codable {
    var auth_token: String? { get set }
}

class Client: NSObject, URLSessionDelegate, ObservableObject {
    enum Error: Swift.Error {
        case clientError(code: Int, message: String)
        case serverError(code: Int, message: String)
    }

    private let endpoint: URL
    private let username: String
    private let password: String
    private var continuations: Continuations = .init()
    private var authorizationToken: String?

    private lazy var configuration = URLSessionConfiguration.default
    private lazy var session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    private lazy var request = URLRequest(url: endpoint)
    private lazy var socket = session.webSocketTask(with: request)
    private lazy var encoder = JSONEncoder()
    private lazy var decoder = JSONDecoder()

    init(host: String, username: String, password: String, port: Int = 5601, path: String = "/api/v1") {
        self.username = username
        self.password = password

        var components = URLComponents()
        components.host = host
        components.port = port
        components.scheme = "wss"
        components.path = path.hasPrefix("/") ? path : "/" + path

        endpoint = components.url!
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

    func handleMessage(_ data: Data) throws {
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

    func getFavoriteHubs(start: Int = 0, count: Int = Int(Int16.max)) async throws -> [Hub] {
        struct Message: AuthorizationToken {
            var auth_token: String?
        }

        let data = try await get(Message(), to: "/favorite_hubs/\(start)/\(count)")
        return try decode([Hub].self, from: data)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.host == "nas" {
            return (.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        } else {
            return (.performDefaultHandling, nil)
        }
    }

    func authorize() async throws -> Authenticate {
        print("authorize")

        struct Message: Codable {
            var username: String
            var password: String
        }

        let message = Message(username: username, password: password)
        let data = try await unauthorizedSend(message, to: "/sessions/authorize", using: .post)
        let response = try decoder.decode(Response<Authenticate>.self, from: data)
        authorizationToken = response.data.auth_token
        print("authorization token: \(authorizationToken ?? "nil")")

        return response.data
    }

    private func get<Data: AuthorizationToken>(_ message: Data, to path: String, operation: String = #function) async throws -> Foundation.Data {
        try await send(message, to: path, using: .get)
    }

    private func post<Data: AuthorizationToken>(_ message: Data, to path: String, operation: String = #function) async throws -> Foundation.Data {
        try await send(message, to: path, using: .post)
    }

    private func send<Data: AuthorizationToken>(_ message: Data, to path: String, using method: Method, operation: String = #function) async throws -> Foundation.Data {
        var newMessage = message

        if let authorizationToken {
            newMessage.auth_token = authorizationToken
        }

        return try await unauthorizedSend(newMessage, to: path, using: method, operation: operation)
    }

    private func unauthorizedSend<Data: Codable>(_ message: Data, to path: String, using method: Method, operation: String = #function) async throws -> Foundation.Data {
        return try await withCheckedThrowingContinuation { continuation in
            let id = continuations.append(continuation)
            let socketMessage = WebSocketMessage<Data>(
                method: method, path: path, callback_id: id, data: message
            )

            print("sending message: \(operation) with ID: \(id)")

            try! socket.send(encode(socketMessage)) {
                if let error = $0 {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func encode<Data: Encodable>(_ message: WebSocketMessage<Data>) throws -> URLSessionWebSocketTask.Message {
        try URLSessionWebSocketTask.Message.data(encoder.encode(message))
    }

    func decode<Data: Codable>(_ type: Data.Type, from data: Foundation.Data) throws -> Data {
        try decoder.decode(Response<Data>.self, from: data).data
    }
}

@main
struct AirDCApp: App {
    @StateObject private var client = Client(
        host: Bundle.main.infoDictionary!["AIRDC_HOST"] as! String,
        username: Bundle.main.infoDictionary!["AIRDC_USERNAME"] as! String,
        password: Bundle.main.infoDictionary!["AIRDC_PASSWORD"] as! String
    )

    var body: some Scene {
        WindowGroup {
            ContentView().task {
//                try! client.connect()
//                let _ = try! await client.authorize()
            }.environmentObject(client)
        }
    }
}
