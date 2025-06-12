import Foundation

public enum Method: String, Codable {
    case post = "POST"
    case get = "GET"
}

struct WebSocketMessage<Data: Codable>: Codable {
    var method: Method
    var path: String
    var callbackId: Int
    var data: Data
}
