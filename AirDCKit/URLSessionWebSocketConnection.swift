import Foundation

public class URLSessionWebSocketConnection: NSObject {
    private let endpoint: URL
    private let host: String

    private lazy var session = Foundation.URLSession(
        configuration: URLSessionConfiguration.default,
        delegate: self,
        delegateQueue: nil
    )

    init(host: String, port: Int = 5601, path: String = "/api/v1") {
        self.host = host
        endpoint = buildURL(host: host, port: port, path: path)
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
