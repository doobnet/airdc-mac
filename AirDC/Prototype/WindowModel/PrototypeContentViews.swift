// PROTOTYPE — throwaway. The content of each Place, shared by every variant so
// the variants differ only in window and navigation structure.

import SwiftUI

extension EnvironmentValues {
  /// How the current variant shows a Place: select it in a sidebar, open a
  /// window, open a tab…
  @Entry var openPlace: (Place) -> Void = { _ in }
}

extension FocusedValues {
  @Entry var openPlace: ((Place) -> Void)?
}

struct PlaceView: View {
  let place: Place

  var body: some View {
    switch place {
    case .favoriteHubs: FavoriteHubsContent()
    case .transfers: TransfersContent()
    case .hub(let name): HubContent(name: name)
    case .privateChat(let nick): PrivateChatContent(nick: nick)
    case .fileList(let nick): FileListContent(nick: nick)
    case .search(let id): SearchContent(id: id)
    }
  }
}

struct PlaceHeader<Trailing: View>: View {
  let systemImage: String
  let title: String
  var subtitle = ""
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage).font(.title2).foregroundStyle(.green)
      Text(title).font(.title2.bold())
      if !subtitle.isEmpty {
        Divider().frame(height: 18)
        Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer()
      trailing
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}

extension PlaceHeader where Trailing == EmptyView {
  init(systemImage: String, title: String, subtitle: String = "") {
    self.init(systemImage: systemImage, title: title, subtitle: subtitle) { EmptyView() }
  }
}

private func bytes(_ value: Int64) -> String {
  value.formatted(.byteCount(style: .binary))
}

private func speed(_ value: Int64) -> String {
  value == 0 ? "" : bytes(value) + "/s"
}

// MARK: - Favorite hubs

struct FavoriteHubsContent: View {
  @Environment(PrototypeSession.self) private var session
  @Environment(\.openPlace) private var openPlace
  @State private var selection: FavoriteHub.ID?

  var body: some View {
    VStack(spacing: 0) {
      PlaceHeader(systemImage: "star", title: "Favorite Hubs", subtitle: "Double-click to connect")
      Table(MockData.favoriteHubs, selection: $selection) {
        TableColumn("Name", value: \.name)
        TableColumn("Address", value: \.address)
        TableColumn("Auto Connect") { Text($0.autoConnect ? "Yes" : "No") }
        TableColumn("State") { Text(session.hubs.contains($0.name) ? "Connected" : "Disconnected") }
      }
      .contextMenu(forSelectionType: FavoriteHub.ID.self) { ids in
        Button("Connect") { ids.forEach { openPlace(.hub($0)) } }
      } primaryAction: { ids in
        ids.forEach { openPlace(.hub($0)) }
      }
    }
  }
}

// MARK: - Hub

struct HubContent: View {
  let name: String
  @Environment(\.openPlace) private var openPlace
  @State private var users: [HubUser]
  @State private var sortOrder = [KeyPathComparator(\HubUser.nick)]
  @State private var selection: HubUser.ID?
  @State private var filter = ""

  init(name: String) {
    self.name = name
    _users = State(initialValue: MockData.users(on: name))
  }

  var body: some View {
    VStack(spacing: 0) {
      PlaceHeader(systemImage: "network", title: name, subtitle: MockData.topics[name] ?? "")
      Divider()
      HSplitView {
        ChatContent(place: .hub(name)).frame(minWidth: 300)
        VStack(spacing: 0) {
          userTable
          HStack {
            TextField("Filter…", text: $filter).textFieldStyle(.roundedBorder)
            Text("\(users.count) users · \(bytes(users.map(\.shareSize).reduce(0, +)))")
              .font(.caption).foregroundStyle(.secondary)
          }
          .padding(8)
        }
        .frame(minWidth: 250)
      }
    }
  }

  private var userTable: some View {
    Table(users.filter { filter.isEmpty || $0.nick.localizedCaseInsensitiveContains(filter) }, selection: $selection, sortOrder: $sortOrder) {
      TableColumn("Nick", value: \.nick)
      TableColumn("Share Size", value: \.shareSize) { Text(bytes($0.shareSize)) }
      TableColumn("Description", value: \.description)
      TableColumn("Tag", value: \.tag)
      TableColumn("Upload Speed", value: \.uploadSpeed) { Text(speed($0.uploadSpeed)) }
      TableColumn("Files", value: \.files) { Text("\($0.files)") }
    }
    .onChange(of: sortOrder) { _, order in users.sort(using: order) }
    .contextMenu(forSelectionType: HubUser.ID.self) { ids in
      Button("Send Private Message") { ids.forEach { openPlace(.privateChat($0)) } }
      Button("Browse File List") { ids.forEach { openPlace(.fileList($0)) } }
    } primaryAction: { ids in
      ids.forEach { openPlace(.privateChat($0)) }
    }
  }
}

struct ChatContent: View {
  let place: Place
  @Environment(PrototypeSession.self) private var session
  @State private var draft = ""

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          ForEach(session.messages[place] ?? []) { line in
            Text("[\(line.time)] ").foregroundStyle(.secondary) + Text("<\(line.nick)> ").bold() + Text(line.text)
          }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
      }
      .defaultScrollAnchor(.bottom)
      .background(.background)
      Divider()
      TextField("Message", text: $draft)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          session.send(draft, to: place)
          draft = ""
        }
        .padding(8)
    }
  }
}

// MARK: - Private messages

struct PrivateChatContent: View {
  let nick: String
  @Environment(\.openPlace) private var openPlace

  var body: some View {
    VStack(spacing: 0) {
      PlaceHeader(systemImage: "person.fill", title: nick, subtitle: "on Sweden's Finest") {
        Button("Browse File List", systemImage: "folder") { openPlace(.fileList(nick)) }
      }
      Divider()
      ChatContent(place: .privateChat(nick))
    }
    .frame(minWidth: 380, minHeight: 300)
  }
}

// MARK: - File lists

struct FileListContent: View {
  let nick: String
  @Environment(PrototypeSession.self) private var session
  @State private var selection: FileEntry.ID?
  @State private var sortOrder = [KeyPathComparator(\FileEntry.name)]

  /// The Daemon keeps one current directory per file list, shared with the
  /// Web UI — so it lives in the session, not in the view. Two views of the
  /// same file list move together.
  private var path: [String] {
    get { session.fileListPaths[nick] ?? [] }
    nonmutating set { session.fileListPaths[nick] = newValue }
  }

  private var directory: FileEntry {
    path.reduce(MockData.fileTree) { dir, name in dir.children?.first { $0.name == name } ?? dir }
  }

  var body: some View {
    VStack(spacing: 0) {
      PlaceHeader(systemImage: "person.fill", title: nick) { breadcrumbs }
      Divider()
      Table((directory.children ?? []).sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
        TableColumn("Name", value: \.name) { Label($0.name, systemImage: $0.isDirectory ? "folder" : "doc") }
        TableColumn("Size", value: \.size) { Text($0.isDirectory ? "" : bytes($0.size)) }
        TableColumn("Type/Content", value: \.type)
      }
      .contextMenu(forSelectionType: FileEntry.ID.self) { ids in
        Button("Download") { download(ids) }
      } primaryAction: { ids in
        guard let name = ids.first, directory.children?.first(where: { $0.name == name })?.isDirectory == true else { return download(ids) }
        path.append(name)
      }
    }
  }

  private var breadcrumbs: some View {
    HStack(spacing: 4) {
      Button("Root") { path = [] }.buttonStyle(.link)
      ForEach(Array(path.enumerated()), id: \.offset) { index, name in
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        Button(name) { path = Array(path.prefix(index + 1)) }.buttonStyle(.link)
      }
    }
  }

  private func download(_ ids: Set<FileEntry.ID>) {
    for entry in directory.children ?? [] where ids.contains(entry.id) {
      session.download(entry.name, size: entry.size)
    }
  }
}

// MARK: - Search

struct SearchContent: View {
  let id: Int
  @Environment(PrototypeSession.self) private var session
  @Environment(\.openPlace) private var openPlace
  @State private var draft = ""
  @State private var selection: SearchResult.ID?

  private var query: String { session.searches.first { $0.id == id }?.query ?? "" }

  var body: some View {
    let results = MockData.searchResults(for: query)
    VStack(spacing: 0) {
      HStack {
        Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.green)
        TextField("Search all hubs", text: $draft)
          .textFieldStyle(.roundedBorder)
          .onSubmit { session.setQuery(draft, of: id) }
        Text(query.isEmpty ? "" : "\(results.count) results").foregroundStyle(.secondary)
      }
      .padding(10)
      Divider()
      Table(results, selection: $selection) {
        TableColumn("Name", value: \.name)
        TableColumn("Size") { Text(bytes($0.size)) }
        TableColumn("Users") { Text("\($0.users)") }
        TableColumn("First User", value: \.firstUser)
        TableColumn("Slots", value: \.slots)
      }
      .contextMenu(forSelectionType: SearchResult.ID.self) { ids in
        Button("Download") { download(ids, from: results) }
        Button("Browse File List") {
          results.filter { ids.contains($0.id) }.forEach { openPlace(.fileList($0.firstUser)) }
        }
      } primaryAction: { ids in
        download(ids, from: results)
      }
    }
    .onAppear { draft = query }
  }

  private func download(_ ids: Set<SearchResult.ID>, from results: [SearchResult]) {
    results.filter { ids.contains($0.id) }.forEach { session.download($0.name, size: $0.size) }
  }
}

// MARK: - Queue and transfers

struct TransfersContent: View {
  @Environment(PrototypeSession.self) private var session
  @State private var tab = 0
  @State private var queueSelection: QueueBundle.ID?
  @State private var transferSelection: Transfer.ID?

  var body: some View {
    VStack(spacing: 0) {
      Picker("", selection: $tab) {
        Text("Queue (\(session.queue.count))").tag(0)
        Text("Transfers (\(MockData.transfers.count))").tag(1)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .padding(6)
      if tab == 0 { queue } else { transfers }
    }
    .frame(minHeight: 140)
  }

  private var queue: some View {
    Table(session.queue, selection: $queueSelection) {
      TableColumn("Name", value: \.name)
      TableColumn("Size") { Text(bytes($0.size)) }
      TableColumn("Status", value: \.status)
      TableColumn("Sources", value: \.sources)
      TableColumn("Speed") { Text(speed($0.speed)) }
      TableColumn("Priority", value: \.priority)
    }
  }

  private var transfers: some View {
    Table(MockData.transfers, selection: $transferSelection) {
      TableColumn("") { Image(systemName: $0.isDownload ? "arrow.down" : "arrow.up") }.width(20)
      TableColumn("User", value: \.user)
      TableColumn("File", value: \.file)
      TableColumn("Speed") { Text(speed($0.speed)) }
      TableColumn("Status", value: \.status)
    }
  }
}

// MARK: - Toolbar

struct ActivityStatus: View {
  @Environment(PrototypeSession.self) private var session

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "clock.arrow.circlepath")
      Text(session.status)
      Spacer(minLength: 0)
      Text("↓ 15.7 MiB/s  ↑ 1 KiB/s").monospacedDigit().foregroundStyle(.secondary)
    }
    .font(.callout)
    .frame(minWidth: 320, maxWidth: 480)
  }
}
