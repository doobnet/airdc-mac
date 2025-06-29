import Foundation
import OSLog

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
