// PROTOTYPE — throwaway. Lives on the `prototype/menu-bar` branch only.
// State for the menu bar prototype: which variant of top-level menus is
// showing, a faked Connection state, and the few App-only flags the menus
// toggle. The hub Session (HubPrototypeState) and the Queue (QueueLab) come
// from the earlier prototypes and hold the selection the menus act on.

import AppKit
import Observation
import SwiftUI

enum MenuVariant: String, CaseIterable {
  case objects, sessionUser, contextual

  var label: String {
    switch self {
    case .objects: "A — Object menus: Session, Hub, User, Queue"
    case .sessionUser: "B — No User menu: user items at the bottom of Session"
    case .contextual: "C — One contextual Session menu (no Hub, no User)"
    }
  }

  /// The top-level menus SwiftUI builds that this variant hides again.
  var hiddenMenus: Set<String> {
    switch self {
    case .objects: []
    case .sessionUser: ["User"]
    case .contextual: ["Hub", "User"]
    }
  }
}

/// Why the App's Connection to the Daemon is down, if it is.
enum ConnectionState: String, CaseIterable {
  case connected, retrying, takenOver, credentialsRejected, certificateChanged

  var label: String {
    switch self {
    case .connected: "Connected"
    case .retrying: "Retrying"
    case .takenOver: "Taken over (1008)"
    case .credentialsRejected: "Credentials rejected"
    case .certificateChanged: "Certificate changed"
    }
  }

  /// The title of File's one Connection item.
  var actionTitle: String {
    switch self {
    case .connected, .retrying, .takenOver: "Reconnect Now"
    case .credentialsRejected: "Sign In…"
    case .certificateChanged: "Review Certificate…"
    }
  }

  var activityText: String {
    switch self {
    case .connected: "Connected to nas:5601"
    case .retrying: "Reconnecting to the Daemon in 30 s"
    case .takenOver: "Another window took over the Daemon session"
    case .credentialsRejected: "The Daemon rejected your password"
    case .certificateChanged: "The Daemon's certificate has changed"
    }
  }
}

/// Who the User items act on: a users-table row, or a Session's peer.
struct FocusedUser {
  let nick: String
  var isIgnored = false
  /// Mention in Chat only makes sense from a Hub's users table.
  var isInHub = false
}

@Observable
final class MenuBarLab {
  var variant = UserDefaults.standard.string(forKey: "menuVariant").flatMap(MenuVariant.init) ?? .objects
  var connection = ConnectionState.connected
  var columnVisibility = NavigationSplitViewVisibility.all
  var chatVisible = true
  var markedUnread: Set<Place> = []
  var markedRead: Set<Place> = []
  var disconnectRequest: Place?
  var suppressDisconnectConfirmation = false
  var lastCommand = "—"

  var isOnline: Bool { connection == .connected }
  var sidebarVisible: Bool { columnVisibility != .detailOnly }

  func log(_ command: String) { lastCommand = command }

  func shift(by offset: Int) {
    let all = MenuVariant.allCases
    variant = all[(all.firstIndex(of: variant)! + offset + all.count) % all.count]
  }
}

/// The Sessions in sidebar order, for Next/Previous Session and Unread.
enum SessionOrder {
  static let all: [Place] = [.favoriteHubs] + HubMock.sidebar.flatMap(\.1)

  static func neighbour(of place: Place?, by offset: Int, among places: [Place] = all) -> Place? {
    guard !places.isEmpty else { return nil }
    let index = place.flatMap { all.firstIndex(of: $0) } ?? 0
    let ordered = (1...all.count).map { all[(index + offset * $0 + all.count * all.count) % all.count] }
    return ordered.first(where: places.contains)
  }
}

extension Place {
  var isSession: Bool { self != .favoriteHubs }

  var isHub: Bool {
    if case .hub = self { return true }
    return false
  }

  var hasTranscript: Bool {
    switch self {
    case .hub, .privateChat: true
    default: false
    }
  }
}

extension HubPrototypeState {
  var selectedHub: String? {
    if case .hub(let name) = selection { return name }
    return nil
  }

  var focusedUser: FocusedUser? {
    switch selection {
    case .hub(HubMock.hubName):
      HubMock.users.first { $0.id == selectedUser }.map { FocusedUser(nick: $0.nick, isIgnored: $0.flags.contains(.ignored), isInHub: true) }
    case .privateChat(let nick): FocusedUser(nick: nick)
    case .fileList(let name): FocusedUser(nick: name)
    default: nil
    }
  }

  func hasUnread(_ place: Place, lab: MenuBarLab) -> Bool {
    if lab.markedUnread.contains(place) { return true }
    if lab.markedRead.contains(place) { return false }
    if place == .hub(HubMock.hubName) { return messages.contains(where: \.isUnread) }
    return HubMock.unread[place] != nil
  }
}
