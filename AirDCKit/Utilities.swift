import Foundation

func buildURL(host: String, port: Int, path: String) -> URL {
    var components = URLComponents()
    components.host = host
    components.port = port
    components.scheme = "wss"
    components.path = path.hasPrefix("/") ? path : "/" + path

    return components.url!
}
