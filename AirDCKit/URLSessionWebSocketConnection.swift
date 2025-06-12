import Foundation

public class URLSessionWebSocketConnection: NSObject {
    private let endpoint: URL
    private let host: String

    private lazy var request = URLRequest(url: endpoint)
    private lazy var transport = session.webSocketTask(with: request)
    private lazy var connection = WebSocketConnection(transport: transport)

    private lazy var session = Foundation.URLSession(
        configuration: URLSessionConfiguration.default,
        delegate: self,
        delegateQueue: nil
    )

    init(host: String, port: Int = 5601, path: String = "/api/v1") {
        self.host = host
        endpoint = buildURL(host: host, port: port, path: path)
    }

    func connect() async throws {
        try await connection.connect()
    }

    func send<Data: Codable>(_ message: Data, to path: String, using method: Method, operation: String = #function) async throws -> Foundation.Data {
        try await connection.send(message, to: path, using: method, operation: operation)
    }
}

extension URLSessionWebSocketConnection: URLSessionDelegate {
    public func urlSession(
        _ session: Foundation.URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (Foundation.URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.host == host {
            return (.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        } else {
            return (.performDefaultHandling, nil)
        }
    }
}

extension URLSessionWebSocketTask: Transport {}

// struct URLSession: Session {
//    private let session: Foundation.URLSession
//
//    init(session: Foundation.URLSession) {
//        self.session = session
//    }
//
//    func webSocketTask(with request: URLRequest) -> Transport {
//        session.webSocketTask(with: request)
//    }
// }
