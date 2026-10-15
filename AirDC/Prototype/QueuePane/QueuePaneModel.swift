// PROTOTYPE — throwaway. Lives on the `prototype/queue-pane` branch only.
// In-memory stand-in for the Daemon's Queue: Bundles, their files (fetched
// on expansion, as the API forces) and sources. A one-second tick moves the
// downloads along, so pausing visibly stops — or doesn't — what's running.
//
// Pause semantics are the Daemon's (airdcpp-core QueueManager):
//   Paused (forced) 0 — running downloads are disconnected at once, even
//                       Highest files stop. "Pause All" in the Web UI.
//   Paused 1          — nothing new starts; running segments finish; files
//                       with Highest priority keep downloading.
//   Auto (-1)         — the Daemon picks a priority. "Resume All" in the Web UI.
// The Daemon itself force-pauses a Bundle on a download error (disk full).

import Foundation
import Observation

enum QueueVariant: String, CaseIterable {
  case outline, downloads, inspector, nativeOutline, outlineButtons

  var label: String {
    switch self {
    case .outline: "A — Outline: columns, priority is the control"
    case .downloads: "B — Downloads list: rows with pause buttons"
    case .inspector: "C — Outline + Bundle inspector"
    case .nativeOutline: "D — Outline: Pause and Priority are commands"
    case .outlineButtons: "E — D + a pause button on each row"
    }
  }
}

/// `Queue priority ID` from the API.
nonisolated enum QueuePriority: Int, CaseIterable, Comparable {
  case pausedForced = 0, paused, lowest, low, normal, high, highest

  static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

  static let running: [QueuePriority] = [.lowest, .low, .normal, .high, .highest]

  var isPaused: Bool { self <= .paused }

  var label: String {
    switch self {
    case .pausedForced: "Paused (forced)"
    case .paused: "Paused"
    case .lowest: "Lowest"
    case .low: "Low"
    case .normal: "Normal"
    case .high: "High"
    case .highest: "Highest"
    }
  }
}

/// `Queue bundle.status.id` from the API.
nonisolated enum BundleStatus: String {
  case queued, downloadError, recheck, downloaded, validationRunning, validationError, completed, shared

  var isFinished: Bool { [.downloaded, .completed, .shared, .validationRunning, .validationError].contains(self) }
}

nonisolated struct QueueSource: Identifiable, Hashable {
  var id: String { nick }
  let nick: String
  let hubs: String
  var lastSpeed: Int64
  let files: Int
  let size: Int64
  var online: Bool
}

nonisolated struct QueueFile: Identifiable, Hashable {
  let id: Int
  let name: String
  let size: Int64
  var downloaded: Int64 = 0
  var priority: QueuePriority = .normal
  var autoPriority = true
  var speed: Int64 = 0

  var progress: Double { size == 0 ? 0 : Double(downloaded) / Double(size) }
  var isFinished: Bool { downloaded >= size }
}

nonisolated struct QueueBundle: Identifiable, Hashable {
  let id: Int
  let name: String
  let target: String
  let isDirectory: Bool
  var size: Int64
  var downloaded: Int64
  var priority: QueuePriority
  var autoPriority: Bool
  var status: BundleStatus = .queued
  var error: String?
  var speed: Int64 = 0
  var baseSpeed: Int64
  var sources: [QueueSource]
  var added: Date
  var finished: Date?
  var fileCount: Int
  var directoryCount = 0
  /// The priority before the App paused it — App-only memory, the Daemon
  /// doesn't keep it.
  var priorityBeforePause: QueuePriority?
  /// Paused (non-forced) Bundles let the running segment finish.
  var segmentTicksLeft = 0

  var progress: Double { size == 0 ? 0 : Double(downloaded) / Double(size) }
  var isFinished: Bool { status.isFinished }
  var isRunning: Bool { speed > 0 }
  var secondsLeft: Int? { isRunning ? Int(Double(size - downloaded) / Double(speed)) : nil }
  var sourcesOnline: Int { sources.filter(\.online).count }
  var sourcesText: String { isFinished ? "" : "\(sourcesOnline)/\(sources.count)" }

  var statusText: String {
    switch status {
    case .downloadError: "Paused · \(error ?? "Download error")"
    case .recheck: "Rechecking…"
    case .downloaded: "Downloaded"
    case .validationRunning: "Validating…"
    case .validationError: "Validation failed"
    case .completed: "Completed"
    case .shared: "Shared"
    case .queued:
      if priority == .pausedForced { "Paused" }
      else if priority == .paused { isRunning ? "Pausing…" : "Paused" }
      else if isRunning { "Downloading" }
      else if sourcesOnline == 0 { "No sources online" }
      else { "Waiting" }
    }
  }

  var priorityText: String {
    if isFinished { return "" }
    return autoPriority && !priority.isPaused ? "\(priority.label) (auto)" : priority.label
  }

  var contentText: String {
    guard isDirectory else { return (name as NSString).pathExtension.uppercased() }
    return directoryCount > 0 ? "\(fileCount) files, \(directoryCount) folders" : "\(fileCount) files"
  }
}

/// The web user's permissions that change what the Queue pane can do.
struct QueuePermissions: Equatable {
  var queueView = true
  var queueEdit = true
}

/// What the App's "Pause" sends. The Daemon has no pause call.
enum PauseKind: String, CaseIterable {
  case forced, soft

  var label: String {
    switch self {
    case .forced: "Paused (forced) — stop now, like the Web UI's Pause All"
    case .soft: "Paused — let running segments and Highest files finish"
    }
  }

  var priority: QueuePriority { self == .forced ? .pausedForced : .paused }
}

/// What the App's "Resume" sends.
enum ResumeKind: String, CaseIterable {
  case auto, previous

  var label: String {
    switch self {
    case .auto: "Auto — let the Daemon pick, like the Web UI's Resume All"
    case .previous: "The priority it had before pausing (App remembers)"
    }
  }
}

@Observable
final class QueueLab {
  var variant = UserDefaults.standard.string(forKey: "queueVariant").flatMap(QueueVariant.init) ?? .outline {
    didSet { UserDefaults.standard.set(variant.rawValue, forKey: "queueVariant") }
  }
  var permissions = QueuePermissions()
  var pauseKind = PauseKind.forced
  var resumeKind = ResumeKind.auto
  var bundles = QueueMock.bundles
  /// Files per Bundle, fetched on first expansion (`GET …/files/{start}/{count}`).
  var files: [Int: [QueueFile]] = [:]
  var loading: Set<Int> = []
  var expanded: Set<Int> = []
  var selection: Set<String> = []
  var lastAction = "—"
  var nextID = 100

  var paneVisible = true

  func shift(by offset: Int) {
    let all = QueueVariant.allCases
    variant = all[(all.firstIndex(of: variant)! + offset + all.count) % all.count]
  }

  // MARK: Totals for the bottom bar

  var downSpeed: Int64 { bundles.map(\.speed).reduce(0, +) }
  var bytesLeft: Int64 { bundles.filter { !$0.isFinished }.map { $0.size - $0.downloaded }.reduce(0, +) }
  var activeCount: Int { bundles.filter { !$0.isFinished }.count }
  var allPaused: Bool { bundles.filter { !$0.isFinished }.allSatisfy(\.priority.isPaused) }

  func bundle(_ id: Int) -> QueueBundle? { bundles.first { $0.id == id } }

  /// The selected Bundles that aren't finished — what Pause, Resume and Priority act on.
  var selectedActiveBundles: [QueueBundle] {
    bundles.filter { selection.contains(QueueRowID.bundle($0.id)) && !$0.isFinished }
  }

  /// A queued file and the Bundle it belongs to.
  func file(_ id: Int) -> (file: QueueFile, bundleID: Int)? {
    for (bundleID, list) in files {
      if let file = list.first(where: { $0.id == id }) { return (file, bundleID) }
    }
    return nil
  }

  // MARK: Expansion — files are only reachable per Bundle, paged.

  func setExpanded(_ id: Int, _ isExpanded: Bool) {
    if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
    guard isExpanded, files[id] == nil, !loading.contains(id) else { return }
    loading.insert(id)
    Task {
      try? await Task.sleep(for: .milliseconds(600))
      files[id] = QueueMock.files(for: bundle(id))
      loading.remove(id)
    }
  }

  // MARK: Actions — each maps to one API call, logged in `lastAction`.

  func pause(_ ids: some Sequence<Int>) {
    for id in ids { setPriority(pauseKind.priority, auto: false, of: id) }
  }

  func resume(_ ids: some Sequence<Int>) {
    for id in ids {
      guard let bundle = bundle(id) else { continue }
      switch resumeKind {
      case .auto: setPriority(.normal, auto: true, of: id)
      case .previous: setPriority(bundle.priorityBeforePause ?? .normal, auto: bundle.priorityBeforePause == nil, of: id)
      }
    }
  }

  func togglePause(_ id: Int) {
    guard let bundle = bundle(id) else { return }
    bundle.priority.isPaused ? resume([id]) : pause([id])
  }

  /// `POST /queue/bundles/{id}/priority {priority}`; auto omits `priority`.
  func setPriority(_ priority: QueuePriority, auto: Bool, of id: Int) {
    guard let index = bundles.firstIndex(where: { $0.id == id }) else { return }
    var bundle = bundles[index]
    if priority.isPaused, !bundle.priority.isPaused { bundle.priorityBeforePause = bundle.autoPriority ? nil : bundle.priority }
    if !priority.isPaused { bundle.priorityBeforePause = nil }
    bundle.priority = priority
    bundle.autoPriority = auto
    if bundle.status == .downloadError, !priority.isPaused { bundle.status = .queued; bundle.error = nil }
    switch priority {
    case .pausedForced: bundle.speed = 0
    case .paused: bundle.segmentTicksLeft = bundle.isRunning ? 3 : 0
    default: break
    }
    bundles[index] = bundle
    lastAction = "POST /queue/bundles/\(id)/priority " + (auto ? "{} (auto)" : "{priority: \(priority.rawValue)}")
  }

  /// `POST /queue/bundles/priority` — every Bundle at once.
  func pauseAll() {
    for bundle in bundles where !bundle.isFinished { setPriority(pauseKind.priority, auto: false, of: bundle.id) }
    lastAction = "POST /queue/bundles/priority {priority: \(pauseKind.priority.rawValue)}"
  }

  func resumeAll() {
    for bundle in bundles where !bundle.isFinished { setPriority(.normal, auto: true, of: bundle.id) }
    lastAction = "POST /queue/bundles/priority {} (auto)"
  }

  /// `POST /queue/files/{id}/priority` — orders downloads inside a Bundle.
  func setFilePriority(_ priority: QueuePriority, auto: Bool, file id: Int, in bundleID: Int) {
    guard let index = files[bundleID]?.firstIndex(where: { $0.id == id }) else { return }
    files[bundleID]![index].priority = priority
    files[bundleID]![index].autoPriority = auto
    lastAction = "POST /queue/files/\(id)/priority " + (auto ? "{priority: -1} (auto)" : "{priority: \(priority.rawValue)}")
  }

  /// `POST /queue/bundles/{id}/remove {remove_finished}`.
  func remove(_ ids: some Sequence<Int>, deletingFinished: Bool) {
    let ids = Set(ids)
    bundles.removeAll { ids.contains($0.id) }
    selection = selection.filter { !ids.contains(QueueRowID.bundleID($0) ?? -1) }
    lastAction = "POST /queue/bundles/{\(ids.map(String.init).joined(separator: ","))}/remove {remove_finished: \(deletingFinished)}"
  }

  /// `POST /queue/bundles/remove_completed` — never deletes files.
  func removeCompleted() {
    bundles.removeAll(where: \.isFinished)
    lastAction = "POST /queue/bundles/remove_completed"
  }

  /// `POST /queue/bundles/{id}/search`.
  func searchForAlternates(_ ids: some Sequence<Int>) {
    lastAction = "POST /queue/bundles/{\(ids.map(String.init).joined(separator: ","))}/search"
  }

  /// `DELETE /queue/bundles/{id}/sources/{cid}`.
  func removeSource(_ nick: String, from id: Int) {
    guard let index = bundles.firstIndex(where: { $0.id == id }) else { return }
    bundles[index].sources.removeAll { $0.nick == nick }
    lastAction = "DELETE /queue/bundles/\(id)/sources/<cid of \(nick)>"
  }

  // MARK: Simulated Daemon events

  /// The Daemon's own reaction to a full disk: force-pause plus download_error.
  func simulateDiskFull() {
    guard let index = bundles.firstIndex(where: { !$0.isFinished && !$0.priority.isPaused }) else { return }
    bundles[index].priority = .pausedForced
    bundles[index].autoPriority = false
    bundles[index].status = .downloadError
    bundles[index].error = "Not enough free space"
    bundles[index].speed = 0
    lastAction = "event queue_bundle_status + queue_bundle_priority (Daemon paused it)"
  }

  /// Something queued under an existing directory Bundle merges into it.
  func simulateMerge() {
    guard let index = bundles.firstIndex(where: { $0.isDirectory && !$0.isFinished }) else { return }
    let file = QueueFile(id: nextID, name: "Bonus - Live at Hultsfred.flac", size: 41_943_040)
    nextID += 1
    bundles[index].size += file.size
    bundles[index].fileCount += 1
    files[bundles[index].id]?.append(file)
    lastAction = "event queue_bundle_content (merged into \(bundles[index].name))"
  }

  func simulateNewBundle() {
    let bundle = QueueBundle(
      id: nextID, name: "archlinux-2026.10.01-x86_64.iso", target: "/mnt/storage/Downloads/", isDirectory: false,
      size: 1_288_490_188, downloaded: 0, priority: .normal, autoPriority: true, baseSpeed: 9_000_000,
      sources: QueueMock.sources(4, online: 3), added: .now, fileCount: 1)
    nextID += 1
    bundles.append(bundle)
    lastAction = "event queue_bundle_added (from the Web UI)"
  }

  func emptyQueue() {
    bundles = []
    lastAction = "Queue emptied"
  }

  func resetQueue() {
    bundles = QueueMock.bundles
    files = [:]
    expanded = []
    lastAction = "Queue reset"
  }

  // MARK: Tick — roughly `queue_bundle_tick` once a second.

  func tick() {
    for index in bundles.indices { advance(&bundles[index]) }
  }

  private func advance(_ bundle: inout QueueBundle) {
    guard bundle.status == .queued, bundle.sourcesOnline > 0 else { bundle.speed = 0; return }
    switch bundle.priority {
    case .pausedForced:
      bundle.speed = 0
      return
    case .paused:
      let highestFileRunning = files[bundle.id]?.contains { $0.priority == .highest && !$0.isFinished } == true
      if highestFileRunning { break }
      guard bundle.segmentTicksLeft > 0 else { bundle.speed = 0; return }
      bundle.segmentTicksLeft -= 1
    default: break
    }
    let jitter = Double.random(in: 0.85...1.15)
    bundle.speed = Int64(Double(bundle.baseSpeed) * jitter * (bundle.priority == .paused ? 0.4 : 1))
    bundle.downloaded = min(bundle.size, bundle.downloaded + bundle.speed)
    advanceFiles(of: bundle)
    if bundle.downloaded >= bundle.size {
      bundle.speed = 0
      bundle.status = .completed
      bundle.finished = .now
    }
  }

  private func advanceFiles(of bundle: QueueBundle) {
    guard var list = files[bundle.id] else { return }
    var remaining = bundle.speed
    let order = list.indices.sorted { list[$0].priority > list[$1].priority }
    for index in order where remaining > 0 && !list[index].isFinished {
      let step = min(remaining, list[index].size - list[index].downloaded)
      list[index].downloaded += step
      list[index].speed = step
      remaining -= step
    }
    for index in list.indices where list[index].isFinished { list[index].speed = 0 }
    files[bundle.id] = list
  }
}

/// Row identities shared by every variant: "b<id>" for Bundles, "f<id>" for
/// files, "l<id>" for a Bundle's loading placeholder.
nonisolated enum QueueRowID {
  static func bundle(_ id: Int) -> String { "b\(id)" }
  static func file(_ id: Int) -> String { "f\(id)" }

  static func bundleID(_ rowID: String) -> Int? {
    rowID.hasPrefix("b") ? Int(rowID.dropFirst()) : nil
  }

  static func fileID(_ rowID: String) -> Int? {
    rowID.hasPrefix("f") ? Int(rowID.dropFirst()) : nil
  }
}

enum QueueMock {
  static func sources(_ count: Int, online: Int) -> [QueueSource] {
    let nicks = ["Foobar", "[100Mbit]Foobar", "DataHoarder", "GigaGustav", "JohanFiber", "MegaShare", "Petra", "Olle"]
    return (0..<count).map { index in
      QueueSource(
        nick: nicks[index % nicks.count], hubs: index % 2 == 0 ? "Sweden's Finest" : "Sweden's Finest, Anime Central",
        lastSpeed: index < online ? Int64(index + 1) * 3_400_000 : 0, files: 3 + index * 2,
        size: Int64(index + 1) * 120_000_000, online: index < online)
    }
  }

  static let bundles: [QueueBundle] = [
    QueueBundle(
      id: 1, name: "Kent - Isola (1997)", target: "/mnt/storage/Downloads/Kent - Isola (1997)/", isDirectory: true,
      size: 366_673_920, downloaded: 338_000_000, priority: .high, autoPriority: true, baseSpeed: 6_400_000,
      sources: sources(1, online: 1), added: .now.addingTimeInterval(-3_600), fileCount: 12),
    QueueBundle(
      id: 2, name: "ubuntu-26.04-desktop-amd64.iso", target: "/mnt/storage/Downloads/", isDirectory: false,
      size: 6_174_015_488, downloaded: 740_000_000, priority: .normal, autoPriority: false, baseSpeed: 11_000_000,
      sources: sources(7, online: 3), added: .now.addingTimeInterval(-7_200), fileCount: 1),
    QueueBundle(
      id: 3, name: "Twin Peaks (2017) S01", target: "/mnt/storage/Downloads/Twin Peaks (2017) S01/", isDirectory: true,
      size: 38_654_705_664, downloaded: 2_100_000_000, priority: .paused, autoPriority: false, baseSpeed: 0,
      sources: sources(5, online: 2), added: .now.addingTimeInterval(-86_400), fileCount: 19, directoryCount: 2),
    QueueBundle(
      id: 4, name: "Linux Journal Archive 1994-2019", target: "/mnt/storage/Downloads/Linux Journal Archive 1994-2019/",
      isDirectory: true, size: 21_474_836_480, downloaded: 0, priority: .lowest, autoPriority: true, baseSpeed: 0,
      sources: sources(3, online: 0), added: .now.addingTimeInterval(-172_800), fileCount: 1_402, directoryCount: 26),
    QueueBundle(
      id: 5, name: "debian-14-netinst.iso", target: "/mnt/storage/Downloads/", isDirectory: false,
      size: 734_003_200, downloaded: 734_003_200, priority: .normal, autoPriority: true, status: .shared,
      baseSpeed: 0, sources: [], added: .now.addingTimeInterval(-90_000),
      finished: .now.addingTimeInterval(-80_000), fileCount: 1),
  ]

  static func files(for bundle: QueueBundle?) -> [QueueFile] {
    guard let bundle, bundle.isDirectory else { return [] }
    let count = min(bundle.fileCount, 40)
    let per = bundle.size / Int64(max(bundle.fileCount, 1))
    var left = bundle.downloaded
    return (0..<count).map { index in
      let done = min(per, max(0, left))
      left -= per
      return QueueFile(
        id: bundle.id * 1_000 + index, name: name(in: bundle, index), size: per, downloaded: done,
        priority: bundle.priority.isPaused ? bundle.priority : .normal, autoPriority: true)
    }
  }

  private static func name(in bundle: QueueBundle, _ index: Int) -> String {
    switch bundle.id {
    case 1:
      let titles = ["Livräddaren", "Things She Said", "Saker man ser", "Bianca", "Elever", "Om du var här", "Innan allting tar slut", "Oprah", "Det finns inga ord", "Glöm vad jag sagt", "Sverige", "747"]
      return String(format: "%02d - %@.flac", index + 1, titles[index % titles.count])
    case 3: return String(format: "Disc %d/Twin.Peaks.S01E%02d.1080p.mkv", index / 10 + 1, index + 1)
    default: return String(format: "%d/LJ-%03d.pdf", 1994 + index / 12, index + 1)
    }
  }
}
