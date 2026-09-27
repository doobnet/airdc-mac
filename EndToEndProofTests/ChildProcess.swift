import Foundation

/// A launched child process whose output goes to a log file.
final class ChildProcess: @unchecked Sendable {
  let log: URL
  private let process = Process()

  init(executable: URL, arguments: [String], log: URL) throws {
    self.log = log
    try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: log.path(percentEncoded: false), contents: nil)
    let handle = try FileHandle(forWritingTo: log)

    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = handle
    process.standardError = handle
    process.standardInput = FileHandle.nullDevice
  }

  func start() throws {
    try process.run()
  }

  func stop() {
    guard process.isRunning else { return }
    process.terminate()
    process.waitUntilExit()
  }
}
