import Darwin
import Foundation

enum Ports {
  /// Asks the kernel for a free loopback TCP port.
  static func free() throws -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }

    var address = loopback(port: 0)
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    try withSockaddr(&address) { guard bind(fd, $0, length) == 0 else { throw POSIXError(.EADDRINUSE) } }
    try withSockaddr(&address) { guard getsockname(fd, $0, &length) == 0 else { throw POSIXError(.EINVAL) } }

    return Int(UInt16(bigEndian: address.sin_port))
  }

  /// Waits until something accepts connections on a loopback port.
  static func waitUntilListening(_ port: Int, timeout: Duration = .seconds(20)) async throws {
    try await Poll.until("port \(port) listening", timeout: timeout) { isListening(port) }
  }

  private static func isListening(_ port: Int) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }

    var address = loopback(port: port)
    return withSockaddr(&address) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
  }

  private static func loopback(port: Int) -> sockaddr_in {
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(port).bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    return address
  }

  private static func withSockaddr<T>(
    _ address: inout sockaddr_in,
    _ body: (UnsafeMutablePointer<sockaddr>) throws -> T
  ) rethrows -> T {
    try withUnsafeMutablePointer(to: &address) {
      try $0.withMemoryRebound(to: sockaddr.self, capacity: 1, body)
    }
  }
}

enum Poll {
  struct TimedOut: Error, CustomStringConvertible {
    let description: String
  }

  /// Re-evaluates `condition` until it returns a value or the timeout passes.
  static func until<T>(
    _ what: String,
    timeout: Duration = .seconds(30),
    condition: () async throws -> T?
  ) async throws -> T {
    let deadline = ContinuousClock.now + timeout

    while ContinuousClock.now < deadline {
      if let value = try await condition() { return value }
      try await Task.sleep(for: .milliseconds(200))
    }

    throw TimedOut(description: "timed out waiting for \(what)")
  }

  static func until(
    _ what: String,
    timeout: Duration = .seconds(30),
    condition: () async throws -> Bool
  ) async throws {
    _ = try await until(what, timeout: timeout) { try await condition() ? true : nil }
  }
}
