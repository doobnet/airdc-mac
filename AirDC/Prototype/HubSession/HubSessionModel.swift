// PROTOTYPE — throwaway. Lives on the `prototype/hub-session` branch only.
// In-memory stand-in for one hub Session's Daemon state. No Connection, no
// persistence. Shapes follow the research (Hub, Chat message, Status message,
// Hub user) closely enough to show what the API forces on the UI.

import Foundation
import Observation

enum HubVariant: String, CaseIterable {
  case classic, conversation, switcher

  var label: String {
    switch self {
    case .classic: "A — Classic split (Sketch): IRC lines + user table"
    case .conversation: "B — Conversation + users inspector"
    case .switcher: "C — Chat or Users, full width"
    }
  }
}

/// `Hub.connect_state.id` from the API.
enum ConnectState: String, CaseIterable {
  case connected, connecting, password, redirect, keyprintMismatch, disconnected

  var label: String {
    switch self {
    case .connected: "Connected"
    case .connecting: "Connecting"
    case .password: "Password"
    case .redirect: "Redirect"
    case .keyprintMismatch: "Keyprint mismatch"
    case .disconnected: "Disconnected"
    }
  }
}

/// The web user's permissions that change what a hub Session can do.
struct Permissions: Equatable {
  var hubsView = true
  var hubsEdit = true
  var hubsSend = true
  var settingsEdit = true
}

enum Place: Hashable {
  case favoriteHubs
  case hub(String)
  case privateChat(String)
  case fileList(String)
  case search(String)

  var systemImage: String {
    switch self {
    case .favoriteHubs: "star"
    case .hub: "network"
    case .privateChat: "person.bubble"
    case .fileList: "folder"
    case .search: "magnifyingglass"
    }
  }

  var title: String {
    switch self {
    case .favoriteHubs: "Favorite Hubs"
    case .hub(let name), .privateChat(let name), .fileList(let name), .search(let name): name
    }
  }
}

struct HubUser: Identifiable, Hashable {
  enum Flag: String { case op, bot, away, favorite, ignored, me, passive }

  let id: Int
  let nick: String
  let shareSize: Int64
  let files: Int
  let description: String
  let tag: String
  let uploadSpeed: Int64
  let downloadSpeed: Int64
  let ip4: String
  let country: String
  let email: String
  let flags: Set<Flag>

  var isOp: Bool { flags.contains(.op) }
  var isBot: Bool { flags.contains(.bot) }
  /// Operators first, then bots, then everyone else — the classic DC order.
  var rank: Int { isOp ? 0 : isBot ? 1 : 2 }

  var symbol: String {
    if flags.contains(.me) { return "person.crop.circle.fill" }
    if isBot { return "gearshape.fill" }
    if isOp { return "key.fill" }
    if flags.contains(.away) { return "moon.fill" }
    return "person.fill"
  }
}

enum Severity: String { case verbose, info, warning, error }

enum HubMessage: Identifiable, Hashable {
  case chat(id: Int, time: String, from: String, text: String, thirdPerson: Bool = false, isRead: Bool = true)
  case status(id: Int, time: String, text: String, severity: Severity = .info)
  /// Not a Daemon message: the App's marker that nothing older exists.
  case historyStart(id: Int)

  var id: Int {
    switch self {
    case .chat(let id, _, _, _, _, _), .status(let id, _, _, _), .historyStart(let id): id
    }
  }

  var sender: String? {
    if case .chat(_, _, let from, _, _, _) = self { return from }
    return nil
  }

  var text: String {
    switch self {
    case .chat(_, _, _, let text, _, _), .status(_, _, let text, _): text
    case .historyStart: ""
    }
  }

  var isUnread: Bool {
    if case .chat(_, _, _, _, _, let isRead) = self { return !isRead }
    return false
  }

  var isMention: Bool { sender != nil && text.localizedCaseInsensitiveContains(HubMock.myNick) }
}

@Observable
final class HubPrototypeState {
  var variant = UserDefaults.standard.string(forKey: "hubVariant").flatMap(HubVariant.init) ?? .classic
  var connectState = UserDefaults.standard.string(forKey: "hubState").flatMap(ConnectState.init) ?? .connected
  var permissions = Permissions()
  var selection: Place? = .hub(HubMock.hubName)
  var usersVisible = true
  var queueVisible = true
  var scopeBarVisible = false
  var infoVisible = false
  var messages = HubMock.messages
  var draft = ""
  var redirectFollowed = false
  var filter = ""
  var scope = "All"
  var showsUsersTab = false
  var selectedUser: HubUser.ID?

  var hubURL: String { redirectFollowed ? HubMock.redirectURL : HubMock.hubURL }
  var isOnline: Bool { connectState == .connected }

  /// Each variant's scope bar scopes; the first is the broadest.
  var scopes: [String] {
    switch variant {
    case .classic: ["All", "Chat", "Users"]
    case .conversation: ["All", "Chat", "Mentions", "Users"]
    case .switcher: showsUsersTab ? ["All Fields", "Nick", "Description", "Tag"] : ["All", "Mentions", "Operators"]
    }
  }

  func showScopeBar() {
    scope = scopes[0]
    filter = ""
    scopeBarVisible = true
  }

  func hideScopeBar() {
    filter = ""
    scopeBarVisible = false
  }

  var visibleMessages: [HubMessage] {
    guard scopeBarVisible else { return messages }
    return messages.filter { message in
      switch scope {
      case "Users", "All Fields", "Nick", "Description", "Tag": return true
      case "Mentions": return message.isMention && matches(message.text)
      case "Operators": return HubMock.users.first { $0.nick == message.sender }?.isOp == true && matches(message.text)
      default: return message.sender == nil ? filter.isEmpty : matches(message.text) || matches(message.sender ?? "")
      }
    }
  }

  var visibleUsers: [HubUser] {
    guard scopeBarVisible, !filter.isEmpty else { return HubMock.users }
    return HubMock.users.filter { user in
      switch scope {
      case "Chat", "Mentions", "Operators": true
      case "Description": matches(user.description)
      case "Tag": matches(user.tag)
      case "Nick", "All", "Users": matches(user.nick)
      default: matches(user.nick) || matches(user.description) || matches(user.tag) || matches(user.ip4)
      }
    }
  }

  private func matches(_ text: String) -> Bool {
    filter.isEmpty || text.localizedCaseInsensitiveContains(filter)
  }

  func send() {
    let text = draft.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return }
    draft = ""
    let id = (messages.map(\.id).max() ?? 0) + 1
    if text.hasPrefix("/me ") {
      messages.append(.chat(id: id, time: "now", from: HubMock.myNick, text: String(text.dropFirst(4)), thirdPerson: true))
    } else if text.hasPrefix("/") {
      messages.append(.status(id: id, time: "now", text: "Command \(text.split(separator: " ")[0]) sent to the Daemon", severity: .verbose))
    } else {
      messages.append(.chat(id: id, time: "now", from: HubMock.myNick, text: text))
    }
  }

  func markAllRead() {
    messages = messages.map {
      if case .chat(let id, let time, let from, let text, let third, _) = $0 {
        return .chat(id: id, time: time, from: from, text: text, thirdPerson: third, isRead: true)
      }
      return $0
    }
  }

  func shift(by offset: Int) {
    let all = HubVariant.allCases
    variant = all[(all.firstIndex(of: variant)! + offset + all.count) % all.count]
  }
}

enum HubMock {
  static let hubName = "Sweden's Finest"
  static let hubURL = "adcs://hub.example.se:2780"
  static let redirectURL = "adcs://hub2.example.se:2780"
  static let myNick = "doob"
  static let topic = "Min share 50 GiB · No slots < 3 · Be nice · New ISO section in /linux, read +rules before asking · Hub hardware sponsored by FiberFolk · Next maintenance Sunday 03:00 CET"

  static let sidebar: [(String, [Place])] = [
    ("Hubs", [.hub(hubName), .hub("Anime Central"), .hub("Linux ISOs")]),
    ("Messages", [.privateChat("Foobar")]),
    ("File Lists", [.fileList("[100Mbit]Foobar")]),
    ("Searches", [.search("ubuntu 26.04")]),
  ]

  static let unread: [Place: Int] = [.hub("Anime Central"): 67, .privateChat("Foobar"): 2]

  static let nicks = [
    "Anna", "Bertil", "Cecilia", "DataHoarder", "EdgeLord", "Frida", "GigaGustav", "Hampus", "Ingrid",
    "JohanFiber", "Kalle", "Lisa", "MegaShare", "Nils", "Olle", "Petra", "QuietGuy", "Rasmus", "Sara",
    "Tobbe", "Ulla", "Viktor", "Wilma", "Yngve", "Åsa", "Örjan", "[100Mbit]Foobar", "xX_leech_Xx",
  ]

  /// ~1,200 users, like a mid-sized public hub. The Daemon sends them unsorted
  /// and in pages; the App keeps the whole list and sorts and filters itself.
  static let users: [HubUser] = {
    var list: [HubUser] = [
      user(0, "HubBot", flags: [.bot, .op], description: "[ BOT ] Hub security"),
      user(1, "Opchat", flags: [.bot], description: "[ BOT ] Operator chat"),
      user(2, "Mattias", flags: [.op], description: "Hub owner — PM for help"),
      user(3, "Lotta", flags: [.op, .away], description: "Op (away)"),
      user(4, myNick, flags: [.me], description: "airdc-mac"),
      user(5, "Foobar", flags: [.favorite], description: "Linux ISOs and FLAC"),
      user(6, "Spammer99", flags: [.ignored], description: "cheap slots!!!"),
    ]
    for index in 7..<1_204 {
      let base = nicks[index % nicks.count]
      let flags: Set<HubUser.Flag> = index % 11 == 0 ? [.away] : index % 7 == 0 ? [.passive] : []
      list.append(user(index, index < nicks.count + 7 ? base : "\(base)\(index)", flags: flags, description: index % 5 == 0 ? "[100Mbit] no slots < 3" : ""))
    }
    return list
  }()

  private static func user(_ index: Int, _ nick: String, flags: Set<HubUser.Flag>, description: String) -> HubUser {
    HubUser(
      id: index,
      nick: nick,
      shareSize: Int64((index * 7919) % 9_000 + 50) * 1_073_741_824,
      files: (index * 4099) % 190_000 + 77,
      description: description,
      tag: "<AirDC++ 4.\(20 + index % 12),M:\(flags.contains(.passive) ? "P" : "A"),H:1/0/\(index % 4),S:\(index % 6 + 2)>",
      uploadSpeed: Int64(index % 5 + 1) * 12_500_000,
      downloadSpeed: Int64(index % 3 + 1) * 12_500_000,
      ip4: "82.\(index % 255).\((index * 7) % 255).\((index * 13) % 255)",
      country: ["SE", "SE", "NO", "FI", "DK", "DE"][index % 6],
      email: index % 9 == 0 ? "\(nick.lowercased())@example.se" : "",
      flags: flags
    )
  }

  static let messages: [HubMessage] = [
    .historyStart(id: 0),
    .status(id: 1, time: "17:58", text: "Connecting to adcs://hub.example.se:2780…"),
    .status(id: 2, time: "17:58", text: "Connected, TLS 1.3 (keyprint trusted)"),
    .chat(id: 3, time: "18:01", from: "HubBot", text: "Welcome to Sweden's Finest! Read +rules. Min share 50 GiB."),
    .chat(id: 4, time: "18:03", from: "Anna", text: "anyone got the new debian netinst?"),
    .chat(id: 5, time: "18:04", from: "Foobar", text: "check my share, /linux/debian"),
    .chat(id: 6, time: "18:04", from: "Foobar", text: "magnet:?xt=urn:tth:LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ&xl=734003200&dn=debian-14-netinst.iso"),
    .chat(id: 7, time: "18:05", from: "Anna", text: "thanks! grabbing it"),
    .chat(id: 8, time: "18:06", from: "Mattias", text: "reminder: maintenance Sunday 03:00, see https://example.se/news"),
    .chat(id: 9, time: "18:07", from: "GigaGustav", text: "shares his whole 40 TiB with the hub", thirdPerson: true),
    .status(id: 10, time: "18:09", text: "Lotta is now away", severity: .verbose),
    .chat(id: 11, time: "18:12", from: "Bertil", text: "doob: is the mac app out yet?", isRead: false),
    .chat(id: 12, time: "18:12", from: "Bertil", text: "want to try it on my NAS", isRead: false),
    .chat(id: 13, time: "18:13", from: "Cecilia", text: "same, the Web UI is fine but a native one would be nice", isRead: false),
    .status(id: 14, time: "18:14", text: "Your share is being refreshed by the Daemon", severity: .warning),
  ]
}

func bytes(_ value: Int64) -> String { value.formatted(.byteCount(style: .binary)) }
func speed(_ value: Int64) -> String { value == 0 ? "" : bytes(value) + "/s" }
