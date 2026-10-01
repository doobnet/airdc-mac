// PROTOTYPE — throwaway. Lives on the `prototype/queue-pane` branch only.
//
// On this branch the hub Session prototype is only the host: the floating
// bar and the Prototype menu switch the queue pane variants instead
// (see QueuePane/QueuePaneVariants.swift).
//
// Originally:
// Question: What does a hub Session look like?
// Three layouts of a hub Session inside the window model settled earlier
// (sidebar, toolbar activity field, Queue pane, bottom bar), switchable from
// the floating bar or the Prototype menu (⌃⌘← / ⌃⌘→):
//
//   A — Classic split (the Sketch): IRC-style lines, user table as a trailing pane
//   B — Conversation: lines grouped by sender, users in a native inspector
//   C — Chat or Users: one full-width view at a time, picked in the toolbar
//
// The floating bar also switches the hub's connect state and the web user's
// permissions, so each layout can be judged in every state the API can put
// it in. ⌘F shows the scope bar, ⌘I hub info.

import AppKit
import SwiftUI

struct HubSessionPrototype: Scene {
  @State private var state = HubPrototypeState()
  @State private var lab = QueueLab()

  var body: some Scene {
    Window("AirDC", id: "main") {
      MainWindow().environment(state).environment(lab)
    }
    .defaultSize(width: 1300, height: 900)
    .restorationBehavior(.disabled)
    .commands { PrototypeCommands(state: state, lab: lab) }
  }
}

/// Launched with `-snapshot <path.png>`, the prototype writes its window to
/// a PNG and quits — for sharing screenshots of each variant.
enum Snapshot {
  static func takeIfRequested() {
    guard let path = UserDefaults.standard.string(forKey: "snapshot") else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
      guard let window = NSApp.windows.filter(\.isVisible).max(by: { $0.frame.width < $1.frame.width }), let view = window.contentView?.superview,
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
      else { return }
      view.cacheDisplay(in: view.bounds, to: rep)
      // Sandboxed: lands in the container's tmp directory.
      let url = FileManager.default.temporaryDirectory.appending(path: path)
      try? rep.representation(using: .png, properties: [:])?.write(to: url)
      NSApp.terminate(nil)
    }
  }
}

struct MainWindow: View {
  @Environment(HubPrototypeState.self) private var state
  @Environment(QueueLab.self) private var lab
  @State private var searchText = ""

  var body: some View {
    @Bindable var state = state
    NavigationSplitView {
      Sidebar().navigationSplitViewColumnWidth(min: 180, ideal: 220)
    } detail: {
      VStack(spacing: 0) {
        if lab.paneVisible {
          VSplitView {
            detail.frame(minHeight: 280).overlay(alignment: .bottom) { QueuePrototypeBar() }
            QueuePaneView()
          }
        } else {
          detail.overlay(alignment: .bottom) { QueuePrototypeBar() }
        }
        Divider()
        QueueBottomBar(showsPauseAll: lab.variant == .inspector)
      }
    }
    .navigationTitle(state.selection?.title ?? "AirDC")
    .navigationSubtitle(subtitle)
    .toolbar {
      ToolbarItem(placement: .principal) { ActivityField() }
    }
    .searchable(text: $searchText, placement: .toolbar, prompt: "Search Files")
    .onAppear { Snapshot.takeIfRequested() }
  }

  private var subtitle: String {
    guard case .hub(let name) = state.selection, state.permissions.hubsView else { return "" }
    return name == HubMock.hubName ? HubMock.topic : ""
  }

  @ViewBuilder private var detail: some View {
    switch state.selection {
    case .hub(HubMock.hubName):
      if state.permissions.hubsView {
        HubSessionView().id(state.variant)
      } else {
        ContentUnavailableView(
          "Hubs Unavailable", systemImage: "lock",
          description: Text("Your web user on the Daemon doesn't have permission to view hubs."))
      }
    case .some(let place):
      ContentUnavailableView(place.title, systemImage: place.systemImage, description: Text("Not part of this prototype — pick Sweden's Finest."))
    case nil:
      ContentUnavailableView("Nothing Selected", systemImage: "sidebar.left")
    }
  }
}

/// The hub Session in the current variant, with the scope bar above it.
struct HubSessionView: View {
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    VStack(spacing: 0) {
      if state.scopeBarVisible { ScopeBar() }
      ConnectBanner()
      switch state.variant {
      case .classic: ClassicHubView()
      case .conversation: ConversationHubView()
      case .switcher: SwitcherHubView()
      }
    }
    .toolbar {
      ToolbarItem {
        @Bindable var state = state
        Button("Get Info", systemImage: "info.circle") { state.infoVisible.toggle() }
          .popover(isPresented: $state.infoVisible) { HubInfo() }
      }
    }
  }
}

// MARK: - Sidebar, queue, bottom bar, toolbar (settled; kept rough)

struct Sidebar: View {
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    @Bindable var state = state
    List(selection: $state.selection) {
      Label("Favorite Hubs", systemImage: "star").tag(Place.favoriteHubs)
      ForEach(HubMock.sidebar, id: \.0) { section, places in
        if section != "Hubs" || state.permissions.hubsView {
          Section(section) {
            ForEach(places, id: \.self) { place in
              Label(place.title, systemImage: symbol(for: place))
                .badge(badge(for: place))
                .tag(place)
            }
          }
        }
      }
    }
    .listStyle(.sidebar)
  }

  private func symbol(for place: Place) -> String {
    place == .hub(HubMock.hubName) && !state.isOnline ? "network.slash" : place.systemImage
  }

  private func badge(for place: Place) -> Int {
    if place == .hub(HubMock.hubName) { return state.messages.filter(\.isUnread).count }
    return HubMock.unread[place] ?? 0
  }
}

struct ActivityField: View {
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "checkmark.circle").foregroundStyle(.green)
      Text("Connected to nas:5601").lineLimit(1)
      Spacer(minLength: 0)
    }
    .font(.callout)
    .frame(minWidth: 280, maxWidth: 420)
  }
}

// MARK: - Menus

struct PrototypeCommands: Commands {
  let state: HubPrototypeState
  let lab: QueueLab

  var body: some Commands {
    CommandGroup(after: .toolbar) {
      Button(state.usersVisible ? "Hide Users" : "Show Users") { state.usersVisible.toggle() }
        .keyboardShortcut("u", modifiers: [.command, .option])
      Button(lab.paneVisible ? "Hide Queue" : "Show Queue") { lab.paneVisible.toggle() }
        .keyboardShortcut("l", modifiers: [.command, .option])
    }
    CommandGroup(after: .textEditing) {
      Button("Filter…") { state.showScopeBar() }.keyboardShortcut("f")
    }
    CommandMenu("Hub") {
      Button("Get Info") { state.infoVisible = true }.keyboardShortcut("i")
      Button("Mark All as Read") { state.markAllRead() }.keyboardShortcut("u", modifiers: [.command, .shift])
      Divider()
      Button("Reconnect") { state.connectState = .connecting }
        .keyboardShortcut("r")
        .disabled(!state.permissions.hubsEdit)
      Button("Clear Chat History…") { state.messages = [] }.disabled(!state.permissions.hubsEdit)
      Divider()
      Button("Disconnect") { state.connectState = .disconnected }.disabled(!state.permissions.hubsEdit)
    }
    QueueCommands(lab: lab)
  }
}

