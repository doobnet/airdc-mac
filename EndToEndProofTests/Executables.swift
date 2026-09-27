import Foundation

/// Finds the Hub and Daemon binaries on the test process's `PATH`.
struct Executables {
  let path: String

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    path = environment["PATH"] ?? ""
  }

  func find(_ name: String) throws -> URL {
    let candidates = path.split(separator: ":").map {
      URL(filePath: String($0)).appending(path: name)
    }

    guard let found = candidates.first(where: isExecutable) else {
      throw Missing(name: name, path: path)
    }

    return found
  }

  private func isExecutable(_ url: URL) -> Bool {
    FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false))
  }

  struct Missing: Error, CustomStringConvertible {
    let name: String
    let path: String

    var description: String { "\(name) not found on PATH: \(path)" }
  }
}
