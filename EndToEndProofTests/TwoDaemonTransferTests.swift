import CryptoKit
import Foundation
import Testing

/// Throwaway proof for "Do two local Daemons search and transfer through a
/// local Luadch Hub?": a Hub and two Daemons on loopback; Daemon B shares a
/// seeded file, Daemon A searches for it, browses B's file list and downloads it.
@Suite(.serialized)
struct TwoDaemonTransferTests {
  @Test func recordsPath() {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? "<unset>"
    print("E2E-PATH: \(path)")
    print("E2E-SANDBOXED: \(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)")
    Attachment.record(path, named: "PATH.txt")
  }

  @Test(.timeLimit(.minutes(1)))
  func searchBrowseAndDownloadOverLoopback() async throws {
    let world = try TestWorld()
    defer { world.stop() }
    try await world.start()

    let a = world.downloader.http
    let clock = ContinuousClock()
    let started = clock.now

    // Search
    let search = try await a.post("search", ["expiration": 10]) as! [String: Any]
    let searchID = "\(search["id"]!)"
    _ = try await a.post("search/\(searchID)/hub_search", ["priority": 5, "query": ["pattern": "wayfinder-proof"]])
    let result = try await Poll.until("search result") {
      (try await a.get("search/\(searchID)/results/0/10") as? [[String: Any]])?.first
    }
    #expect(result["name"] as? String == "wayfinder-proof.bin")
    print("E2E-SEARCH: result after \(clock.now - started)")

    // File list
    let user = (result["users"] as! [String: Any])["user"] as! [String: Any]
    let cid = user["cid"] as! String
    _ = try await a.post("filelists", ["user": ["cid": cid, "hub_url": user["hub_url"]!], "directory": "/"])
    try await Poll.until("file list loaded") {
      let list = try await a.get("filelists/\(cid)") as? [String: Any]
      return (list?["state"] as? [String: Any])?["id"] as? String == "loaded"
    }
    let listing = try await a.get("filelists/\(cid)/items/0/100") as! [String: Any]
    let names = (listing["items"] as! [[String: Any]]).compactMap { $0["name"] as? String }
    #expect(names == ["Seed"])
    print("E2E-FILELIST: \(names) after \(clock.now - started)")

    // Download
    let resultID = "\(result["id"]!)"
    _ = try await a.post(
      "search/\(searchID)/results/\(resultID)/download",
      ["target_directory": world.downloader.downloads.path(percentEncoded: false) + "/"]
    )
    let target = world.downloader.downloads.appending(path: "wayfinder-proof.bin")
    let downloaded = try await Poll.until("download complete") {
      (try? Data(contentsOf: target)).flatMap { $0.count == world.payload.count ? $0 : nil }
    }
    #expect(SHA256.hash(data: downloaded) == SHA256.hash(data: world.payload))
    print("E2E-DOWNLOAD: \(downloaded.count) bytes after \(clock.now - started)")
  }
}

/// One Hub, a downloading Daemon (A) and a sharing Daemon (B) in a temp directory.
final class TestWorld {
  let hub: LocalHub
  let downloader: LocalDaemon
  let sharer: LocalDaemon
  let payload = Data((0..<(3 * 1024 * 1024 + 17)).map { _ in UInt8.random(in: .min ... .max) })
  private let root: URL

  init(executables: Executables = Executables()) throws {
    root = FileManager.default.temporaryDirectory.appending(path: "e2e-\(UUID().uuidString)")
    let seed = root.appending(path: "seed")
    try FileManager.default.createDirectory(at: seed.appending(path: "Album"), withIntermediateDirectories: true)
    try payload.write(to: seed.appending(path: "Album/wayfinder-proof.bin"))
    try Data("hello\n".utf8).write(to: seed.appending(path: "Album/other.txt"))

    let airdcppd = try executables.find("airdcppd")
    hub = try LocalHub(launcher: try executables.find("luadch"), directory: root.appending(path: "hub"))
    downloader = try LocalDaemon(executable: airdcppd, directory: root.appending(path: "a"), nick: "daemon-a", hubURL: hub.url)
    sharer = try LocalDaemon(
      executable: airdcppd, directory: root.appending(path: "b"), nick: "daemon-b", hubURL: hub.url, shareRoot: seed
    )
  }

  func start() async throws {
    try await hub.start()
    try await downloader.start()
    try await sharer.start()
    try await downloader.waitUntilJoined()
    try await sharer.waitUntilJoined()
    try await sharer.waitUntilSharing(files: 2)
    print("E2E-ROOT: \(root.path(percentEncoded: false))")
  }

  func stop() {
    downloader.stop()
    sharer.stop()
    hub.stop()
  }
}
