// PROTOTYPE — throwaway. Lives on the `prototype/menu-bar` branch only.
// The App's whole menu bar. Every variant declares the same menus; SwiftUI
// can't branch inside `Commands`, so MenuBarHider hides the top-level Hub and
// User menus a variant doesn't have, and the Session menu's lower section
// switches on the variant itself.
//
// Commands are stubs: each logs the call it would make in the floating bar.
// Unavailable items are disabled, never hidden. Key equivalents are only the
// settled ones; everything else is open.

import AppKit
import SwiftUI

struct MenuBarCommands: Commands {
  let lab: MenuBarLab
  let hub: HubPrototypeState
  let queue: QueueLab

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New Search") { lab.log("Opens a new search Session") }
        .keyboardShortcut("f", modifiers: [.command, .option])
        .disabled(!lab.isOnline)
    }
    CommandGroup(replacing: .saveItem) { FileItems(lab: lab, hub: hub) }
    CommandGroup(replacing: .textEditing) {
      Button("Find…") { find() }.keyboardShortcut("f")
    }
    CommandGroup(replacing: .toolbar) { ViewItems(lab: lab, hub: hub, queue: queue) }
    // Read here so the Commands body, not only the item views, follows the variant.
    CommandMenu("Session") { SessionItems(lab: lab, hub: hub, variant: lab.variant) }
    CommandMenu("Hub") { HubItems(lab: lab, hub: hub, showsTentative: true) }
    CommandMenu("User") { UserItems(lab: lab, hub: hub) }
    CommandMenu("Queue") { QueueMenuItems(lab: lab, queue: queue) }
    CommandGroup(replacing: .help) {
      Button("AirDC Help") { lab.log("Opens AirDC Help (stub)") }
    }
  }

  private func find() {
    if hub.selection == .hub(HubMock.hubName) {
      hub.showScopeBar()
      lab.log("⌘F: focuses the users filter (no scope bar in a hub Session)")
    } else {
      lab.log("⌘F: opens the scope bar")
    }
  }
}

// MARK: - File

struct FileItems: View {
  let lab: MenuBarLab
  let hub: HubPrototypeState

  var body: some View {
    Button("Close Window") { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w")
    Button(closeTitle) { close() }
      .disabled(!(hub.selection?.isSession ?? false) || !lab.isOnline)
    Divider()
    Button(lab.connection.actionTitle) {
      lab.log("\(lab.connection.actionTitle): connecting…")
      lab.connection = .connected
    }
    .disabled(lab.isOnline)
    Button("Open Web UI in Browser") { lab.log("Opens https://nas:5601 in the browser") }
  }

  private var closeTitle: String {
    guard let place = hub.selection, place.isSession else { return "Close Session" }
    return "Close “\(place.title)”"
  }

  private func close() {
    guard let place = hub.selection else { return }
    if place.isHub {
      HubDisconnect.request(place, lab: lab)
    } else {
      lab.log("DELETE the “\(place.title)” Session on the Daemon")
    }
  }
}

/// Closing a hub Session is Disconnect: the Daemon only has `DELETE /hubs/{id}`.
enum HubDisconnect {
  static func request(_ place: Place, lab: MenuBarLab) {
    if lab.suppressDisconnectConfirmation {
      perform(place, lab: lab)
    } else {
      lab.disconnectRequest = place
    }
  }

  static func perform(_ place: Place, lab: MenuBarLab) {
    lab.log("DELETE /hubs/{id} — disconnects “\(place.title)” and closes its Session")
  }
}

// MARK: - View

struct ViewItems: View {
  let lab: MenuBarLab
  let hub: HubPrototypeState
  let queue: QueueLab

  var body: some View {
    Button(lab.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
      lab.columnVisibility = lab.sidebarVisible ? .detailOnly : .all
    }
    .keyboardShortcut("s", modifiers: [.command, .control])
    Button(queue.paneVisible ? "Hide Queue" : "Show Queue") { queue.paneVisible.toggle() }
      .keyboardShortcut("l", modifiers: [.command, .option])
    Divider()
    Button(lab.chatVisible ? "Hide Chat" : "Show Chat") { toggleChat() }.disabled(!isHub)
    Button(hub.usersVisible ? "Hide Users" : "Show Users") { toggleUsers() }
      .keyboardShortcut("u", modifiers: [.command, .option])
      .disabled(!isHub)
    Divider()
    Button("Show Event Log") { lab.log("Opens the Event log popover from the activity field") }
    Divider()
  }

  private var isHub: Bool { hub.selection?.isHub ?? false }

  /// At least one half of a hub Session is always visible.
  private func toggleChat() {
    lab.chatVisible.toggle()
    if !lab.chatVisible { hub.usersVisible = true }
    lab.log(lab.chatVisible ? "Shows the chat half" : "Hides the chat half (not drawn in this prototype)")
  }

  private func toggleUsers() {
    hub.usersVisible.toggle()
    if !hub.usersVisible { lab.chatVisible = true }
  }
}

// MARK: - Session

struct SessionItems: View {
  let lab: MenuBarLab
  let hub: HubPrototypeState
  let variant: MenuVariant

  var body: some View {
    Button("Favorite Hubs") { hub.selection = .favoriteHubs }.keyboardShortcut("1")
    Divider()
    Button("Next Session") { move(by: 1) }.keyboardShortcut(.tab, modifiers: .control)
    Button("Previous Session") { move(by: -1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
    Button("Next Unread") { move(by: 1, among: unread) }
      .keyboardShortcut(.downArrow, modifiers: [.command, .option])
      .disabled(unread.isEmpty)
    Button("Previous Unread") { move(by: -1, among: unread) }
      .keyboardShortcut(.upArrow, modifiers: [.command, .option])
      .disabled(unread.isEmpty)
    Divider()
    MarkReadItem(lab: lab, hub: hub)
    Button("Jump to Latest") { lab.log("Scrolls the transcript to the latest message") }
      .keyboardShortcut(.downArrow)
      .disabled(!(hub.selection?.hasTranscript ?? false))
    Button("Jump to Oldest") { lab.log("Scrolls the transcript to the oldest message") }
      .keyboardShortcut(.upArrow)
      .disabled(!(hub.selection?.hasTranscript ?? false))
    lowerSection
  }

  @ViewBuilder private var lowerSection: some View {
    switch variant {
    case .objects:
      EmptyView()
    case .sessionUser:
      UserItems(lab: lab, hub: hub)
    case .contextual:
      ContextualItems(lab: lab, hub: hub)
    }
  }

  private var unread: [Place] { SessionOrder.all.filter { $0 != hub.selection && hub.hasUnread($0, lab: lab) } }

  private func move(by offset: Int, among places: [Place] = SessionOrder.all) {
    hub.selection = SessionOrder.neighbour(of: hub.selection, by: offset, among: places)
  }
}

struct MarkReadItem: View {
  let lab: MenuBarLab
  let hub: HubPrototypeState

  var body: some View {
    let place = hub.selection
    let isUnread = place.map { hub.hasUnread($0, lab: lab) } ?? false
    Button(isUnread ? "Mark as Read" : "Mark as Unread") {
      guard let place else { return }
      isUnread ? markRead(place) : markUnread(place)
    }
    .keyboardShortcut("u", modifiers: [.command, .shift])
    .disabled(!(place?.hasTranscript ?? false))
  }

  private func markRead(_ place: Place) {
    lab.markedUnread.remove(place)
    lab.markedRead.insert(place)
    if place == .hub(HubMock.hubName) { hub.markAllRead() }
    lab.log("messages/read for “\(place.title)”")
  }

  private func markUnread(_ place: Place) {
    lab.markedRead.remove(place)
    lab.markedUnread.insert(place)
    lab.log("App-only unread flag on “\(place.title)” (the Daemon has no “mark unread”)")
  }
}

/// Variant C: the Session menu's lower section follows the selected Session's kind.
struct ContextualItems: View {
  let lab: MenuBarLab
  let hub: HubPrototypeState

  var body: some View {
    Section("Tentative (Q6)") {
      Button("Connect to Hub…") { lab.log("Opens Connect to Hub (tentative)") }.disabled(!lab.isOnline)
    }
    switch hub.selection {
    case .hub(let name):
      Section("Hub: \(name)") { HubItems(lab: lab, hub: hub, showsTentative: false) }
      UserItems(lab: lab, hub: hub)
    case .privateChat, .fileList:
      UserItems(lab: lab, hub: hub)
    default:
      EmptyView()
    }
  }
}

// MARK: - Hub

struct HubItems: View {
  let lab: MenuBarLab
  let hub: HubPrototypeState
  let showsTentative: Bool

  var body: some View {
    if showsTentative {
      Section("Tentative (Q6)") {
        Button("Connect to Hub…") { lab.log("Opens Connect to Hub (tentative)") }.disabled(!lab.isOnline)
        Button("Add to Favorite Hubs") { lab.log("POST /favorite_hubs for \(name ?? "") (tentative)") }
          .disabled(name == nil || !lab.isOnline)
      }
    } else {
      Button("Add to Favorite Hubs (tentative)") { lab.log("POST /favorite_hubs for \(name ?? "") (tentative)") }
        .disabled(name == nil || !lab.isOnline)
    }
    Button("Get Info") { hub.infoVisible = true }.disabled(name == nil)
    Button("Reconnect") {
      hub.connectState = .connecting
      lab.log("POST /hubs/{id}/reconnect")
    }
    .disabled(name == nil || !lab.isOnline || !isHubDown)
    Button("Clear Chat History…") {
      hub.messages = []
      lab.log("POST /hubs/{id}/messages/clear (after a confirmation)")
    }
    .disabled(name == nil || !lab.isOnline)
    Divider()
    Button("Disconnect") { hub.selection.map { HubDisconnect.request($0, lab: lab) } }
      .disabled(name == nil || !lab.isOnline)
  }

  private var name: String? { hub.selectedHub }

  /// Reconnect is for a Hub that's already disconnected.
  private var isHubDown: Bool { ![.connected, .connecting].contains(hub.connectState) }
}

// MARK: - User

struct UserItems: View {
  let lab: MenuBarLab
  let hub: HubPrototypeState

  var body: some View {
    let user = hub.focusedUser
    Section(user.map { "User: \($0.nick)" } ?? "No User in Focus") {
      Button("Send Private Message") { act("Opens a private message Session with", user) }
        .disabled(user == nil || !lab.isOnline || isPrivateChat)
      Button("Browse File List") { act("POST /filelists — opens the file list of", user) }
        .disabled(user == nil || !lab.isOnline || isFileList)
      Button("Mention in Chat") {
        hub.draft += "\(user?.nick ?? ""): "
        act("Inserts a mention in the message field of", user)
      }
      .disabled(!(user?.isInHub ?? false))
      Divider()
      Button("Grant Extra Slot") { act("POST /users/{cid}/grant_slot for", user) }
        .disabled(user == nil || !lab.isOnline)
      Button(user?.isIgnored ?? false ? "Unignore" : "Ignore") { act("POST /users/{cid}/ignore for", user) }
        .disabled(user == nil || !lab.isOnline)
      Divider()
      Button("Copy Nick") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(user?.nick ?? "", forType: .string)
        act("Copied the nick of", user)
      }
      .disabled(user == nil)
    }
  }

  private var isPrivateChat: Bool {
    if case .privateChat = hub.selection { return true }
    return false
  }

  private var isFileList: Bool {
    if case .fileList = hub.selection { return true }
    return false
  }

  private func act(_ text: String, _ user: FocusedUser?) {
    lab.log("\(text) \(user?.nick ?? "—")")
  }
}

// MARK: - Queue

struct QueueMenuItems: View {
  let lab: MenuBarLab
  let queue: QueueLab

  var body: some View {
    let active = queue.selectedActiveBundles
    let selected = queue.bundles.filter { queue.selection.contains(QueueRowID.bundle($0.id)) }
    let canEdit = lab.isOnline
    Button("Pause") { queue.pause(active.map(\.id)) }
      .disabled(!canEdit || !active.contains { !$0.priority.isPaused })
    Button("Resume") { queue.resume(active.map(\.id)) }
      .disabled(!canEdit || !active.contains(where: \.priority.isPaused))
    Menu("Priority") {
      ForEach(priorities, id: \.title) { item in
        Button(item.title) { active.forEach { queue.setPriority(item.priority, auto: item.auto, of: $0.id) } }
      }
    }
    .disabled(!canEdit || active.isEmpty)
    Divider()
    Button("Show Sources…") { lab.log("Opens the Show Sources popover for \(active.first?.name ?? "")") }
      .disabled(active.count != 1)
    Button("Search for Alternates") { queue.searchForAlternates(active.map(\.id)) }
      .disabled(!canEdit || active.isEmpty)
    Button("Remove…") { RemoveConfirmation.run(selected, lab: queue) }
      .keyboardShortcut(.delete)
      .disabled(!canEdit || selected.isEmpty)
    Divider()
    Button("Pause All") { queue.pauseAll() }.disabled(!canEdit || queue.allPaused)
    Button("Resume All") { queue.resumeAll() }
      .disabled(!canEdit || !queue.bundles.contains { !$0.isFinished && $0.priority.isPaused })
    Button("Remove Completed") { queue.removeCompleted() }
      .disabled(!canEdit || !queue.bundles.contains(where: \.isFinished))
  }

  private var priorities: [(title: String, priority: QueuePriority, auto: Bool)] {
    [("Auto", .normal, true)] + QueuePriority.running.reversed().map { ($0.label, $0, false) } + [("Paused", .pausedForced, false)]
  }
}
