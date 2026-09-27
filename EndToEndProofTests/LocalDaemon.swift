import Foundation

/// An `airdcppd` with its own config directory, seeded by files before launch.
final class LocalDaemon {
  let http: DaemonHTTP
  let downloads: URL
  private let process: ChildProcess

  init(executable: URL, directory: URL, nick: String, hubURL: String, shareRoot: URL? = nil) throws {
    let config = directory.appending(path: "cfg")
    downloads = directory.appending(path: "downloads")
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

    let configuration = DaemonConfiguration(
      nick: nick,
      webPort: try Ports.free(),
      connectionPorts: (try Ports.free(), try Ports.free(), try Ports.free()),
      downloads: downloads,
      hubURL: hubURL,
      shareRoot: shareRoot
    )
    try configuration.write(to: config)

    http = DaemonHTTP(port: configuration.webPort, username: configuration.username, password: configuration.password)
    process = try ChildProcess(
      executable: executable,
      arguments: ["-c=\(config.path(percentEncoded: false))"],
      log: directory.appending(path: "airdcppd.log")
    )
  }

  func start() async throws {
    try process.start()
    try await Ports.waitUntilListening(http.port)
  }

  func stop() {
    process.stop()
  }

  func waitUntilJoined() async throws {
    try await Poll.until("hub joined on port \(http.port)") {
      let hubs = try await http.get("hubs") as? [[String: Any]] ?? []
      return !hubs.isEmpty && hubs.allSatisfy { ($0["connect_state"] as? [String: Any])?["id"] as? String == "connected" }
    }
  }

  func waitUntilSharing(files count: Int) async throws {
    try await Poll.until("\(count) files shared on port \(http.port)") {
      let stats = try await http.get("share/stats") as? [String: Any]
      return (stats?["total_file_count"] as? Int ?? 0) >= count
    }
  }
}
