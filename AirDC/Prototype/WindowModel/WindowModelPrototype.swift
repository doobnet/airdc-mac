// PROTOTYPE — throwaway. Lives on the `prototype/window-model` branch only.
//
// Question: What is the App's window and navigation model?
// Four variants of the App's scenes, switchable at runtime from the floating
// bar at the bottom of the main window, or the Prototype menu (⌃⌘← / ⌃⌘→):
//
//   A — One window, sidebar, persistent queue pane (the Sketch files)
//   B — A window per thing (hub, PM, file list, search, transfers)
//   C — Native window tabs (every thing is a tab; drag one out to split it off)
//   D — Mix: Finder-style sidebar windows — many windows and tabs, each with
//       its own selection, pop-out to a window, transfers in the sidebar
//
// All state is in memory (PrototypeSession); nothing talks to a Daemon.

import AppKit
import SwiftUI

enum PrototypeVariant: String, CaseIterable {
  case sidebar, windows, windowTabs, mix

  static let storageKey = "windowModelPrototype.variant"

  static var current: PrototypeVariant {
    UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init) ?? .sidebar
  }

  var label: String {
    switch self {
    case .sidebar: "A — One window, sidebar"
    case .windows: "B — A window per thing"
    case .windowTabs: "C — Native window tabs"
    case .mix: "D — Mix: sidebar windows + tabs + pop-out"
    }
  }

  var shift: (Int) -> PrototypeVariant {
    { offset in
      let all = Self.allCases
      return all[(all.firstIndex(of: self)! + offset + all.count) % all.count]
    }
  }
}

struct WindowModelPrototype: Scene {
  @State private var session = PrototypeSession()

  var body: some Scene {
    WindowGroup("AirDC", id: "main") {
      MainWindow().environment(session)
    }
    .defaultSize(width: 1300, height: 820)
    .commands { PrototypeCommands(session: session) }

    WindowGroup("Detail", id: "detail", for: Place.self) { $place in
      if let place { DetailWindow(place: place).environment(session) }
    }
    .defaultSize(width: 1000, height: 640)
  }
}

// MARK: - Main window

struct MainWindow: View {
  @AppStorage(PrototypeVariant.storageKey) private var variant = PrototypeVariant.sidebar

  var body: some View {
    Group {
      switch variant {
      case .sidebar: SidebarShell(showsQueuePane: true, allowsPopOut: false)
      case .windows, .windowTabs: FavoritesHome()
      case .mix: SidebarShell(showsQueuePane: false, allowsPopOut: true)
      }
    }
    .id(variant)
    .overlay(alignment: .bottom) { VariantSwitcher() }
    .background(WindowAccessor { PrototypeTabbing.configure($0) })
  }
}

/// Variant A and D: a source list of everything open, detail on the right.
struct SidebarShell: View {
  let showsQueuePane: Bool
  let allowsPopOut: Bool
  @Environment(PrototypeSession.self) private var session
  @Environment(\.openWindow) private var openWindow
  @State private var selection: Place? = .hub("Sweden's Finest")
  @State private var queuePaneVisible = true
  @State private var searchText = ""

  var body: some View {
    NavigationSplitView {
      sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 220)
    } detail: {
      detail
    }
    .navigationTitle(selection.map(session.title(of:)) ?? "AirDC")
    .toolbar {
      ToolbarItem(placement: .principal) { ActivityStatus() }
      if showsQueuePane {
        ToolbarItem {
          Toggle(isOn: $queuePaneVisible) { Label("Queue", systemImage: "rectangle.bottomthird.inset.filled") }
            .keyboardShortcut("l", modifiers: [.command, .option])
        }
      }
    }
    .searchable(text: $searchText, placement: .toolbar, prompt: "Search all hubs")
    .onSubmit(of: .search) {
      let place = session.newSearch()
      if case .search(let id) = place { session.setQuery(searchText, of: id) }
      show(place)
    }
    .environment(\.openPlace, show)
    .focusedSceneValue(\.openPlace, show)
  }

  private func show(_ place: Place) {
    session.start(place)
    selection = place
  }

  private var sidebar: some View {
    List(selection: $selection) {
      row(.favoriteHubs)
      if allowsPopOut { row(.transfers) }
      Section("Hubs") { ForEach(session.hubs, id: \.self) { row(.hub($0)) } }
      Section("Messages") { ForEach(session.privateChats, id: \.self) { row(.privateChat($0)) } }
      Section("File Lists") { ForEach(session.fileLists, id: \.self) { row(.fileList($0)) } }
      Section("Searches") { ForEach(session.searches) { row(.search($0.id)) } }
    }
    .listStyle(.sidebar)
  }

  private func row(_ place: Place) -> some View {
    Label(session.title(of: place), systemImage: place.systemImage)
      .badge(session.unread[place] ?? 0)
      .tag(place)
      .contextMenu {
        if allowsPopOut {
          Button("Open in New Window") { openWindow(value: place) }
          Button("Open in New Tab") {
            PrototypeTabbing.nextWindowIsTab = true
            openWindow(value: place)
          }
          Divider()
        }
        Button("Close") {
          if selection == place { selection = nil }
          session.close(place)
        }
      }
  }

  @ViewBuilder private var detail: some View {
    let content = Group {
      if let selection {
        PlaceView(place: selection).id(selection)
      } else {
        ContentUnavailableView("Nothing Selected", systemImage: "sidebar.left")
      }
    }
    if showsQueuePane && queuePaneVisible {
      VSplitView {
        content.frame(minHeight: 250)
        TransfersContent()
      }
    } else {
      content
    }
  }
}

/// Variant B and C: the main window is only the favorite hubs; everything
/// else opens in a window (B) or a tab (C).
struct FavoritesHome: View {
  @Environment(PrototypeSession.self) private var session
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    FavoriteHubsContent()
      .navigationTitle("Favorite Hubs")
      .toolbar { ToolbarItem(placement: .principal) { ActivityStatus() } }
      .environment(\.openPlace, open)
      .focusedSceneValue(\.openPlace, open)
  }

  private func open(_ place: Place) {
    session.start(place)
    openWindow(value: place)
  }
}

struct DetailWindow: View {
  let place: Place
  @Environment(PrototypeSession.self) private var session
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    PlaceView(place: place)
      .navigationTitle(session.title(of: place))
      .environment(\.openPlace, open)
      .focusedSceneValue(\.openPlace, open)
      .background(WindowAccessor { PrototypeTabbing.configure($0) })
      .onAppear { session.start(place) }
  }

  private func open(_ place: Place) {
    session.start(place)
    openWindow(value: place)
  }
}

// MARK: - Menus

struct PrototypeCommands: Commands {
  let session: PrototypeSession
  @AppStorage(PrototypeVariant.storageKey) private var variant = PrototypeVariant.sidebar
  @Environment(\.openWindow) private var openWindow
  @FocusedValue(\.openPlace) private var openPlace

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      if variant == .mix {
        Button("New Window") { openWindow(id: "main") }.keyboardShortcut("n")
        Button("New Tab") {
          PrototypeTabbing.nextWindowIsTab = true
          openWindow(id: "main")
        }
        .keyboardShortcut("t")
      }
      Button("New Search") { openPlace?(session.newSearch()) }.keyboardShortcut("f", modifiers: [.command, .shift])
      Button("Favorite Hubs") { openPlace?(.favoriteHubs) }.keyboardShortcut("0")
      if variant != .sidebar {
        Button("Transfers") { openPlace?(.transfers) }.keyboardShortcut("l", modifiers: [.command, .option])
      }
    }
    CommandMenu("Prototype") {
      ForEach(PrototypeVariant.allCases, id: \.self) { candidate in
        Toggle(candidate.label, isOn: .init(get: { variant == candidate }, set: { _ in switchTo(candidate) }))
      }
      Divider()
      Button("Previous Variant") { switchTo(variant.shift(-1)) }.keyboardShortcut(.leftArrow, modifiers: [.command, .control])
      Button("Next Variant") { switchTo(variant.shift(1)) }.keyboardShortcut(.rightArrow, modifiers: [.command, .control])
    }
  }

  private func switchTo(_ candidate: PrototypeVariant) {
    PrototypeTabbing.closeSecondaryWindows()
    variant = candidate
  }
}

// MARK: - Variant switcher

struct VariantSwitcher: View {
  @AppStorage(PrototypeVariant.storageKey) private var variant = PrototypeVariant.sidebar

  var body: some View {
    HStack(spacing: 14) {
      Button { switchTo(variant.shift(-1)) } label: { Image(systemName: "chevron.left") }
      Text(variant.label).font(.callout.weight(.semibold))
      Button { switchTo(variant.shift(1)) } label: { Image(systemName: "chevron.right") }
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.black.opacity(0.85), in: Capsule())
    .shadow(radius: 8)
    .padding(.bottom, 14)
  }

  private func switchTo(_ candidate: PrototypeVariant) {
    PrototypeTabbing.closeSecondaryWindows()
    variant = candidate
  }
}

// MARK: - AppKit window plumbing

enum PrototypeTabbing {
  static let identifier = "airdc"
  static var nextWindowIsTab = false

  /// C: every window joins one tab group. D: only windows opened with "New
  /// Tab". Others follow the system "Prefer tabs" setting.
  static func configure(_ window: NSWindow) {
    let variant = PrototypeVariant.current
    let wantsTab = variant == .windowTabs || nextWindowIsTab
    nextWindowIsTab = false
    window.tabbingIdentifier = identifier
    window.tabbingMode = variant == .windowTabs ? .preferred : .automatic
    guard wantsTab, window.tabbedWindows?.count ?? 1 <= 1 else { return }
    let host = NSApp.orderedWindows.first { $0 !== window && $0.isVisible && $0.tabbingIdentifier == identifier }
    host?.addTabbedWindow(window, ordered: .above)
    window.makeKeyAndOrderFront(nil)
  }

  static func closeSecondaryWindows() {
    let windows = NSApp.windows.filter { $0.tabbingIdentifier == identifier && $0.isVisible }
    let mains = windows.filter { $0.identifier?.rawValue.hasPrefix("main") == true }
    for window in windows where window !== mains.first { window.close() }
  }
}

struct WindowAccessor: NSViewRepresentable {
  let configure: (NSWindow) -> Void

  func makeNSView(context: Context) -> AccessorView {
    let view = AccessorView()
    view.configure = configure
    return view
  }

  func updateNSView(_ nsView: AccessorView, context: Context) {}

  final class AccessorView: NSView {
    var configure: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard let window else { return }
      DispatchQueue.main.async { [configure] in configure?(window) }
    }
  }
}
