import Foundation
import OSLog
import Network

public func tap<T>(_ value: T, operation: (_: T) -> Void) -> T {
    operation(value)
    return value
}

public enum Logging {
  static let subsystem = "com.github.doobnet.AirDCKit"
  public static let disabledLogger = Logger(OSLog.disabled)

  public static func newLogger(category: String = #file) -> Logger {
    Logger(subsystem: subsystem, category: category)
  }
}

public func buildURL(scheme: String? = "wss", host: String, port: NWEndpoint.Port, path: String = "") -> URL {
  buildURL(scheme: scheme, host: host, port: Int(port.rawValue), path: path)
}

public func buildURL(scheme: String? = "wss", host: String, port: Int, path: String = "") -> URL {
    var components = URLComponents()
    components.host = host
    components.port = port
    components.scheme = scheme
    components.path = path.hasPrefix("/") ? path : "/" + path

    return components.url!
}
