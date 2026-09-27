// PROTOTYPE — throwaway. Lives on the `prototype/hub-session` branch only.
//
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

  var body: some Scene {
    Window("AirDC", id: "main") {
      MainWindow().environment(state)
    }
    .defaultSize(width: 1300, height: 820)
    .restorationBehavior(.disabled)
    .commands { PrototypeCommands(state: state) }
  }
}

/// Launched with `-snapshot <path.png>`, the prototype writes its window to
/// a PNG and quits — for sharing screenshots of each variant.
enum Snapshot {
  static func takeIfRequested() {
    guard let path = UserDefaults.standard.string(forKey: "snapshot") else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
      guard let window = NSApp.windows.first(where: \.isVisible), let view = window.contentView?.superview,
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
  @State private var searchText = ""

  var body: some View {
    @Bindable var state = state
    NavigationSplitView {
      Sidebar().navigationSplitViewColumnWidth(min: 180, ideal: 220)
    } detail: {
      VStack(spacing: 0) {
        if state.queueVisible {
          VSplitView {
            detail.frame(minHeight: 280)
            QueuePane()
          }
        } else {
          detail
        }
        Divider()
        BottomBar()
      }
    }
    .navigationTitle(state.selection?.title ?? "AirDC")
    .navigationSubtitle(subtitle)
    .toolbar {
      ToolbarItem(placement: .principal) { ActivityField() }
    }
    .searchable(text: $searchText, placement: .toolbar, prompt: "Search Files")
    .overlay(alignment: .bottom) { PrototypeBar() }
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

struct QueuePane: View {
  var body: some View {
    Table(of: QueueRow.self) {
      TableColumn("Name", value: \.name)
      TableColumn("Size", value: \.size)
      TableColumn("Status", value: \.status)
      TableColumn("Sources", value: \.sources)
      TableColumn("Speed", value: \.speed)
    } rows: {
      TableRow(QueueRow(name: "Kent - Isola (1997)", size: "349.68 MiB", status: "Running (92.2%)", sources: "1/1 online", speed: "15.7 MiB/s"))
      TableRow(QueueRow(name: "debian-14-netinst.iso", size: "700 MiB", status: "Waiting (12.0%)", sources: "3/7 online", speed: ""))
    }
    .frame(minHeight: 110, maxHeight: 200)
  }

  struct QueueRow: Identifiable {
    var id: String { name }
    let name, size, status, sources, speed: String
  }
}

struct BottomBar: View {
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    HStack {
      Text("↓ 15.7 MiB/s  ↑ 1 KiB/s  ·  Queue 2 Bundles, 1.02 GiB").monospacedDigit()
      Spacer()
      Button(state.queueVisible ? "Hide Queue" : "Show Queue", systemImage: "rectangle.bottomthird.inset.filled") {
        state.queueVisible.toggle()
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
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

  var body: some Commands {
    CommandGroup(after: .toolbar) {
      Button(state.usersVisible ? "Hide Users" : "Show Users") { state.usersVisible.toggle() }
        .keyboardShortcut("u", modifiers: [.command, .option])
      Button(state.queueVisible ? "Hide Queue" : "Show Queue") { state.queueVisible.toggle() }
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
    CommandMenu("Prototype") {
      ForEach(HubVariant.allCases, id: \.self) { candidate in
        Toggle(candidate.label, isOn: .init(get: { state.variant == candidate }, set: { _ in state.variant = candidate }))
      }
      Divider()
      Button("Previous Variant") { state.shift(by: -1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .control])
      Button("Next Variant") { state.shift(by: 1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .control])
    }
  }
}

// MARK: - Floating prototype bar

struct PrototypeBar: View {
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    @Bindable var state = state
    HStack(spacing: 14) {
      Button { state.shift(by: -1) } label: { Image(systemName: "chevron.left") }
      Text(state.variant.label).font(.callout.weight(.semibold))
      Button { state.shift(by: 1) } label: { Image(systemName: "chevron.right") }
      Divider().frame(height: 14).overlay(.white.opacity(0.4))
      Menu("State: \(state.connectState.label)") {
        Picker("Connect State", selection: $state.connectState) {
          ForEach(ConnectState.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.inline)
      }
      .fixedSize()
      Menu("Permissions") {
        Toggle("hubs_view", isOn: $state.permissions.hubsView)
        Toggle("hubs_edit", isOn: $state.permissions.hubsEdit)
        Toggle("hubs_send", isOn: $state.permissions.hubsSend)
        Toggle("settings_edit (ignore, grant slot)", isOn: $state.permissions.settingsEdit)
      }
      .fixedSize()
    }
    .buttonStyle(.plain)
    .menuStyle(.button)
    .foregroundStyle(.white)
    .tint(.white)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.black.opacity(0.85), in: Capsule())
    .shadow(radius: 8)
    .padding(.bottom, 34)
  }
}
