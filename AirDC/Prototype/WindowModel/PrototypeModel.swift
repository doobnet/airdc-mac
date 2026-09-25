// PROTOTYPE — throwaway. Lives on the `prototype/window-model` branch only.
// In-memory stand-in for Daemon state so the window-model variants have
// something realistic to show. No Connection, no persistence.

import Foundation
import Observation

enum Place: Hashable, Codable, Identifiable {
  case favoriteHubs
  case transfers
  case hub(String)
  case privateChat(String)
  case fileList(String)
  case search(Int)

  var id: Self { self }

  var systemImage: String {
    switch self {
    case .favoriteHubs: "star"
    case .transfers: "arrow.up.arrow.down"
    case .hub: "network"
    case .privateChat: "person.bubble"
    case .fileList: "folder"
    case .search: "magnifyingglass"
    }
  }
}

struct ChatLine: Identifiable, Hashable {
  let id = UUID()
  let time: String
  let nick: String
  let text: String
}

struct FavoriteHub: Identifiable, Hashable {
  var id: String { name }
  let name: String
  let address: String
  let autoConnect: Bool
}

struct HubUser: Identifiable, Hashable {
  var id: String { nick }
  let nick: String
  let shareSize: Int64
  let description: String
  let tag: String
  let uploadSpeed: Int64
  let files: Int
}

struct FileEntry: Identifiable, Hashable {
  var id: String { name }
  let name: String
  let size: Int64
  var children: [FileEntry]? = nil
  var isDirectory: Bool { children != nil }
  var type: String { isDirectory ? "\(children!.count) items" : (name as NSString).pathExtension.uppercased() }
}

struct SearchResult: Identifiable, Hashable {
  let id = UUID()
  let name: String
  let size: Int64
  let users: Int
  let firstUser: String
  let slots: String
}

struct QueueBundle: Identifiable, Hashable {
  let id = UUID()
  let name: String
  let size: Int64
  let status: String
  let sources: String
  let speed: Int64
  let priority: String
}

struct Transfer: Identifiable, Hashable {
  let id = UUID()
  let user: String
  let file: String
  let isDownload: Bool
  let speed: Int64
  let status: String
}

struct SearchState: Identifiable, Hashable {
  let id: Int
  var query: String
}

@Observable
final class PrototypeSession {
  var hubs = ["Sweden's Finest", "Anime Central"]
  var privateChats = ["Foobar"]
  var fileLists = ["[100Mbit]Foobar"]
  var searches = [SearchState(id: 1, query: "ubuntu 26.04")]
  var messages: [Place: [ChatLine]] = MockData.messages
  var unread: [Place: Int] = [.hub("Anime Central"): 67, .privateChat("Foobar"): 2]
  var fileListPaths: [String: [String]] = [:]
  var queue = MockData.queue
  var status = "Foobar downloaded"

  func title(of place: Place) -> String {
    switch place {
    case .favoriteHubs: "Favorite Hubs"
    case .transfers: "Transfers"
    case .hub(let name), .privateChat(let name), .fileList(let name): name
    case .search(let id): searches.first { $0.id == id }.map { $0.query.isEmpty ? "New Search" : $0.query } ?? "Search"
    }
  }

  func start(_ place: Place) {
    unread[place] = nil
    switch place {
    case .hub(let name): appendIfMissing(&hubs, name)
    case .privateChat(let nick): appendIfMissing(&privateChats, nick)
    case .fileList(let nick): appendIfMissing(&fileLists, nick)
    case .favoriteHubs, .transfers, .search: break
    }
  }

  func close(_ place: Place) {
    switch place {
    case .hub(let name): hubs.removeAll { $0 == name }
    case .privateChat(let nick): privateChats.removeAll { $0 == nick }
    case .fileList(let nick): fileLists.removeAll { $0 == nick }
    case .search(let id): searches.removeAll { $0.id == id }
    case .favoriteHubs, .transfers: break
    }
  }

  func newSearch() -> Place {
    let id = (searches.map(\.id).max() ?? 0) + 1
    searches.append(SearchState(id: id, query: ""))
    return .search(id)
  }

  func setQuery(_ query: String, of id: Int) {
    guard let index = searches.firstIndex(where: { $0.id == id }) else { return }
    searches[index].query = query
  }

  func send(_ text: String, to place: Place) {
    messages[place, default: []].append(ChatLine(time: "now", nick: "me", text: text))
  }

  func download(_ name: String, size: Int64) {
    queue.append(QueueBundle(name: name, size: size, status: "Queued", sources: "1/1 online", speed: 0, priority: "Normal"))
    status = "Queued \(name)"
  }

  private func appendIfMissing(_ list: inout [String], _ value: String) {
    if !list.contains(value) { list.append(value) }
  }
}

enum MockData {
  static let favoriteHubs = [
    FavoriteHub(name: "Sweden's Finest", address: "adcs://hub.example.se:2780", autoConnect: true),
    FavoriteHub(name: "Anime Central", address: "adc://anime.example.org:1511", autoConnect: true),
    FavoriteHub(name: "Linux ISOs", address: "nmdcs://iso.example.net:411", autoConnect: false),
    FavoriteHub(name: "Retro Games", address: "adcs://retro.example.com:2780", autoConnect: false),
  ]

  static let topics = [
    "Sweden's Finest": "Min share 50 GiB · No slots < 3 · Be nice",
    "Anime Central": "Fansubs only. Read the rules with +rules",
  ]

  static let nicks = [
    "Foobar", "[100Mbit]Foobar", "xX_leech_Xx", "HubBot", "Anna", "Bertil", "Cecilia", "DataHoarder",
    "EdgeLord", "Frida", "GigaGustav", "Hampus", "Ingrid", "JohanFiber", "Kalle", "Lisa", "MegaShare",
    "Nils", "Olle", "Petra", "QuietGuy", "Rasmus", "Sara", "Tobbe", "Ulla", "Viktor", "Wilma", "Yngve",
  ]

  static func users(on hub: String) -> [HubUser] {
    nicks.enumerated().map { index, nick in
      HubUser(
        nick: nick,
        shareSize: Int64((index * 7919 + hub.count * 31) % 9000 + 50) * 1_073_741_824,
        description: nick == "HubBot" ? "[ BOT ]" : "",
        tag: "<AirDC++ 4.\(index % 30),M:A,H:1/0/\(index % 4)>",
        uploadSpeed: Int64(index % 5 + 1) * 12_500_000,
        files: (index * 4099) % 90_000 + 77
      )
    }
  }

  static let messages: [Place: [ChatLine]] = [
    .hub("Sweden's Finest"): [
      ChatLine(time: "18:01", nick: "HubBot", text: "Welcome to Sweden's Finest! Read +rules."),
      ChatLine(time: "18:03", nick: "Anna", text: "anyone got the new debian netinst?"),
      ChatLine(time: "18:04", nick: "Foobar", text: "check my share, /linux/debian"),
    ],
    .hub("Anime Central"): [
      ChatLine(time: "17:40", nick: "HubBot", text: "Rules are strict here."),
      ChatLine(time: "17:52", nick: "Sara", text: "new episode is up"),
    ],
    .privateChat("Foobar"): [
      ChatLine(time: "18:05", nick: "Foobar", text: "hey, could you grant me a slot?"),
      ChatLine(time: "18:05", nick: "Foobar", text: "only need one file"),
    ],
  ]

  static let fileTree = FileEntry(name: "Root", size: 0, children: [
    FileEntry(name: "linux", size: 0, children: [
      FileEntry(name: "debian", size: 0, children: [
        FileEntry(name: "debian-14-netinst.iso", size: 734_003_200),
        FileEntry(name: "SHA256SUMS", size: 1_024),
      ]),
      FileEntry(name: "ubuntu-26.04-desktop-amd64.iso", size: 6_174_015_488),
    ]),
    FileEntry(name: "music", size: 0, children: [
      FileEntry(name: "Kent - Isola (1997)", size: 0, children: [
        FileEntry(name: "01 - Livräddaren.flac", size: 31_457_280),
        FileEntry(name: "02 - Things She Said.flac", size: 29_360_128),
      ]),
    ]),
    FileEntry(name: "readme.txt", size: 2_048),
  ])

  static func searchResults(for query: String) -> [SearchResult] {
    guard !query.isEmpty else { return [] }
    return (1...12).map { index in
      SearchResult(
        name: "\(query.replacingOccurrences(of: " ", with: "-"))-\(["desktop", "server", "live"][index % 3])-amd64-\(index).iso",
        size: Int64(index * 523) * 1_048_576,
        users: 13 - index,
        firstUser: nicks[index % nicks.count],
        slots: "\(index % 4)/\(index % 4 + 3)"
      )
    }
  }

  static let queue = [
    QueueBundle(name: "Kent - Isola (1997)", size: 366_673_920, status: "Running (92.2%)", sources: "1/1 online", speed: 16_441_344, priority: "High (auto)"),
    QueueBundle(name: "ubuntu-26.04-desktop-amd64.iso", size: 6_174_015_488, status: "Waiting (12.0%)", sources: "3/7 online", speed: 0, priority: "Normal"),
    QueueBundle(name: "debian-14-netinst.iso", size: 734_003_200, status: "Finished", sources: "—", speed: 0, priority: "Normal"),
  ]

  static let transfers = [
    Transfer(user: "Foobar", file: "02 - Things She Said.flac", isDownload: true, speed: 16_441_344, status: "Downloaded 14.8 MiB (51%)"),
    Transfer(user: "Anna", file: "linux/debian/SHA256SUMS", isDownload: false, speed: 1_024, status: "Uploaded 1 KiB (100%)"),
    Transfer(user: "GigaGustav", file: "ubuntu-26.04-desktop-amd64.iso", isDownload: true, speed: 0, status: "Connecting…"),
  ]
}
