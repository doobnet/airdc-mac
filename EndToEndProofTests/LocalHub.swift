import Foundation

/// A Luadch Hub on loopback, started through the `luadch` launcher on `PATH`.
final class LocalHub {
  let port: Int
  private let process: ChildProcess

  var url: String { "adc://127.0.0.1:\(port)" }

  init(launcher: URL, directory: URL) throws {
    port = try Ports.free()
    process = try ChildProcess(
      executable: launcher,
      arguments: [directory.appending(path: "instance").path(percentEncoded: false), String(port)],
      log: directory.appending(path: "hub.log")
    )
  }

  func start() async throws {
    try process.start()
    try await Ports.waitUntilListening(port)
  }

  func stop() {
    process.stop()
  }
}
