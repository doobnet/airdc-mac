// PROTOTYPE — throwaway. Lives on the `prototype/menu-bar` branch only.
//
// Question: which top-level menus does the App's menu bar have, and in what order?
// Three variants of the full menu bar, over the main window from the earlier
// prototypes (hub Session layout A, queue pane variant D):
//
//   A — objects:     AirDC File Edit View Session Hub User Queue Window Help
//   B — sessionUser: AirDC File Edit View Session Hub Queue Window Help
//                    (user items at the bottom of Session)
//   C — contextual:  AirDC File Edit View Session Queue Window Help
//                    (Session's lower section follows the selected Session's kind)
//
// Launch with `-menuVariant objects|sessionUser|contextual`, or switch at
// runtime from the floating bar. The bar also fakes the Connection going down
// and the selected Hub disconnecting; pick a Session kind in the sidebar.

import AppKit
import SwiftUI

struct MenuBarPrototype: Scene {
  @State private var lab = MenuBarLab()
  @State private var hub = HubPrototypeState()
  @State private var queue: QueueLab = {
    let queue = QueueLab()
    queue.variant = .nativeOutline
    return queue
  }()

  var body: some Scene {
    Window("AirDC", id: "main") {
      MenuBarWindow().environment(lab).environment(hub).environment(queue)
    }
    .defaultSize(width: 1300, height: 900)
    .restorationBehavior(.disabled)
    .keyboardShortcut("0")
    .commands { MenuBarCommands(lab: lab, hub: hub, queue: queue) }

    Settings {
      Text("Settings (stub)").frame(width: 400, height: 200)
    }
  }
}

struct MenuBarWindow: View {
  @Environment(MenuBarLab.self) private var lab
  @Environment(HubPrototypeState.self) private var hub
  @Environment(QueueLab.self) private var queue
  @State private var searchText = ""

  var body: some View {
    @Bindable var lab = lab
    NavigationSplitView(columnVisibility: $lab.columnVisibility) {
      Sidebar().navigationSplitViewColumnWidth(min: 180, ideal: 220)
    } detail: {
      VStack(spacing: 0) {
        if queue.paneVisible {
          VSplitView {
            detail.frame(minHeight: 280).overlay(alignment: .bottom) { MenuBarPrototypeBar() }
            QueuePaneView()
          }
        } else {
          detail.overlay(alignment: .bottom) { MenuBarPrototypeBar() }
        }
        Divider()
        QueueBottomBar(showsPauseAll: false)
      }
    }
    .navigationTitle(hub.selection?.title ?? "AirDC")
    .toolbar {
      ToolbarItem(placement: .principal) { MenuBarActivityField() }
    }
    .searchable(text: $searchText, placement: .toolbar, prompt: "Search Files")
    .confirmationDialog(
      "Disconnect from “\(lab.disconnectRequest?.title ?? "")”?",
      isPresented: .init(get: { lab.disconnectRequest != nil }, set: { if !$0 { lab.disconnectRequest = nil } })
    ) {
      Button("Disconnect", role: .destructive) { lab.disconnectRequest.map { HubDisconnect.perform($0, lab: lab) } }
    } message: {
      Text("The Daemon leaves the Hub, and its Session closes in the Web UI too.")
    }
    .dialogSuppressionToggle("Don't ask again", isSuppressed: $lab.suppressDisconnectConfirmation)
    .onAppear {
      MenuBarHider.start(lab)
      AlternateSessionKeys.start(hub)
      MenuDump.runIfRequested(lab, hub: hub)
      Snapshot.takeIfRequested()
    }
    .onChange(of: lab.variant) { MenuBarHider.apply(lab.variant) }
    .onChange(of: queue.lastAction) { lab.log(queue.lastAction) }
  }

  @ViewBuilder private var detail: some View {
    switch hub.selection {
    case .hub(HubMock.hubName):
      HubSessionView().id(hub.variant)
    case .hub(let name):
      stub(name, "network", "Another hub Session. Hub items act on it; its users table isn't drawn.")
    case .privateChat(let nick):
      stub(nick, "person.bubble", "A private message Session. The user in focus is its peer, \(nick).")
    case .fileList(let nick):
      stub(nick, "folder", "A file list Session. The user in focus is its owner, \(nick).")
    case .search(let query):
      stub(query, "magnifyingglass", "A search Session. No user is in focus.")
    case .favoriteHubs:
      stub("Favorite Hubs", "star", "Not a Session: nothing to close or mark as read.")
    case nil:
      ContentUnavailableView("Nothing Selected", systemImage: "sidebar.left")
    }
  }

  private func stub(_ title: String, _ symbol: String, _ text: String) -> some View {
    ContentUnavailableView(title, systemImage: symbol, description: Text(text))
  }
}

struct MenuBarActivityField: View {
  @Environment(MenuBarLab.self) private var lab

  var body: some View {
    HStack(spacing: 6) {
      if lab.isOnline {
        Image(systemName: "checkmark.circle").foregroundStyle(.green)
      } else {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
      }
      Text(lab.connection.activityText).lineLimit(1)
      Spacer(minLength: 0)
    }
    .font(.callout)
    .frame(minWidth: 280, maxWidth: 420)
  }
}

/// ⇧⌘] / ⇧⌘[ also move between Sessions. A menu item shows one key
/// equivalent, so the menu shows ⌃⇥ / ⌃⇧⇥ and these work without showing.
@MainActor enum AlternateSessionKeys {
  private static var monitor: Any?

  static func start(_ hub: HubPrototypeState) {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let offsets: [UInt16: Int] = [30: 1, 33: -1]  // ] and [
      guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
        let offset = offsets[event.keyCode]
      else { return event }
      hub.selection = SessionOrder.neighbour(of: hub.selection, by: offset)
      return nil
    }
  }
}

/// SwiftUI can't leave a CommandMenu out conditionally, so the variant hides
/// the top-level items it doesn't have — again whenever SwiftUI rebuilds them.
/// It also hides the leading, trailing and doubled separators SwiftUI leaves
/// around menu sections.
@MainActor enum MenuBarHider {
  private static var observers: [NSObjectProtocol] = []

  static func start(_ lab: MenuBarLab) {
    apply(lab.variant)
    guard observers.isEmpty else { return }
    observers = [NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification, NSMenu.didBeginTrackingNotification].map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { apply(lab.variant) }
      }
    }
  }

  static func apply(_ variant: MenuVariant) {
    DispatchQueue.main.async {
      for item in NSApp.mainMenu?.items ?? [] {
        setHidden(item, variant.hiddenMenus.contains(item.title))
        item.submenu.map(tidySeparators)
      }
    }
  }

  private static func tidySeparators(_ menu: NSMenu) {
    var previousIsSeparator = true
    for item in menu.items where !item.isHidden || item.isSeparatorItem {
      if item.isSeparatorItem {
        setHidden(item, previousIsSeparator)
        previousIsSeparator = true
      } else {
        previousIsSeparator = item.isSectionHeader
      }
    }
    if let last = menu.items.last(where: { !$0.isHidden }), last.isSeparatorItem { setHidden(last, true) }
    menu.items.compactMap(\.submenu).forEach(tidySeparators)
  }

  /// Only writes on a change: every write posts another menu notification.
  private static func setHidden(_ item: NSMenuItem, _ hidden: Bool) {
    if item.isHidden != hidden { item.isHidden = hidden }
  }
}

struct MenuBarPrototypeBar: View {
  @Environment(MenuBarLab.self) private var lab
  @Environment(HubPrototypeState.self) private var hub

  var body: some View {
    @Bindable var lab = lab
    @Bindable var hub = hub
    VStack(spacing: 4) {
      HStack(spacing: 14) {
        Button { lab.shift(by: -1) } label: { Image(systemName: "chevron.left") }
        Text(lab.variant.label).font(.callout.weight(.semibold)).lineLimit(1)
        Button { lab.shift(by: 1) } label: { Image(systemName: "chevron.right") }
        Divider().frame(height: 14).overlay(.white.opacity(0.4))
        Menu("Connection: \(lab.connection.label)") {
          Picker("Connection", selection: $lab.connection) {
            ForEach(ConnectionState.allCases, id: \.self) { Text($0.label).tag($0) }
          }
          .pickerStyle(.inline)
        }
        .fixedSize()
        Menu("Hub: \(hub.connectState.label)") {
          Picker("Hub", selection: $hub.connectState) {
            ForEach(ConnectState.allCases, id: \.self) { Text($0.label).tag($0) }
          }
          .pickerStyle(.inline)
        }
        .fixedSize()
      }
      Text(lab.lastCommand).font(.caption.monospaced()).opacity(0.75).lineLimit(1).truncationMode(.middle)
    }
    .buttonStyle(.plain)
    .menuStyle(.button)
    .foregroundStyle(.white)
    .tint(.white)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .frame(maxWidth: 820)
    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
    .shadow(radius: 8)
    .padding(.bottom, 56)
  }
}

/// Launched with `-dumpMenus <file.txt>`, the prototype writes every variant's
/// menu bar as text (title, key equivalent, disabled, hidden) and quits.
@MainActor enum MenuDump {
  static func runIfRequested(_ lab: MenuBarLab, hub: HubPrototypeState) {
    guard let path = UserDefaults.standard.string(forKey: "dumpMenus") else { return }
    let scenarios: [(String, Place, HubUser.ID?)] = [
      ("hub Session, users row Foobar selected", .hub(HubMock.hubName), 5),
      ("private message Session with Foobar", .privateChat("Foobar"), nil),
    ]
    Task {
      var text = ""
      for variant in MenuVariant.allCases {
        for (name, place, user) in scenarios {
          lab.variant = variant
          hub.selection = place
          hub.selectedUser = user
          try? await Task.sleep(for: .seconds(1.5))
          MenuBarHider.apply(variant)
          try? await Task.sleep(for: .seconds(0.5))
          text += "=== \(variant.label) — \(name)\n" + describe(NSApp.mainMenu, depth: 0)
        }
      }
      // Sandboxed: lands in the container's tmp directory.
      try? text.write(to: FileManager.default.temporaryDirectory.appending(path: path), atomically: true, encoding: .utf8)
      NSApp.terminate(nil)
    }
  }

  private static func describe(_ menu: NSMenu?, depth: Int) -> String {
    // What opening the menu does: SwiftUI refreshes its items lazily.
    if let menu, depth > 0 {
      menu.delegate?.menuNeedsUpdate?(menu)
      menu.delegate?.menuWillOpen?(menu)
      menu.update()
      menu.delegate?.menuDidClose?(menu)
    }
    return (menu?.items ?? []).map { item in
      let indent = String(repeating: "  ", count: depth)
      if item.isHidden, depth > 0 { return "" }
      if item.isSeparatorItem { return indent + "----\n" }
      if item.isSectionHeader { return indent + "[\(item.title)]\n" }
      var line = indent + item.title
      if !item.keyEquivalent.isEmpty { line += "  " + shortcut(item) }
      if !item.isEnabled { line += "  (disabled)" }
      if item.isHidden { line += "  (HIDDEN)" }
      return line + "\n" + describe(item.submenu, depth: depth + 1)
    }.joined()
  }

  private static func shortcut(_ item: NSMenuItem) -> String {
    let flags = item.keyEquivalentModifierMask
    let names: [String: String] = [
      "\t": "⇥", "\u{8}": "⌫", "\u{7f}": "⌫",
      String(UnicodeScalar(NSUpArrowFunctionKey)!): "↑", String(UnicodeScalar(NSDownArrowFunctionKey)!): "↓",
    ]
    return (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "")
      + (flags.contains(.command) ? "⌘" : "") + (names[item.keyEquivalent] ?? item.keyEquivalent.uppercased())
  }
}
