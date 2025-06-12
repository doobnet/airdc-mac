import Foundation
import OSLog

struct Logging {
    static let subsystem = "com.github.doobnet.AirDCKit"

    static func newLogger(category: String = #file) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}

func buildURL(host: String, port: Int, path: String) -> URL {
    var components = URLComponents()
    components.host = host
    components.port = port
    components.scheme = "wss"
    components.path = path.hasPrefix("/") ? path : "/" + path

    return components.url!
}
