// PROTOTYPE — throwaway. The three hub Session layouts.

import SwiftUI

// MARK: - A — Classic split

/// The Sketch: IRC-style lines on the left, a many-column user table as a
/// trailing pane that collapses first when the window gets narrow. Operators
/// and bots always sort first, like DC++.
struct ClassicHubView: View {
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    GeometryReader { geometry in
      HSplitView {
        VStack(spacing: 0) {
          ClassicTranscript()
          MessageInput()
        }
        .frame(minWidth: 340)
        if state.usersVisible && geometry.size.width > 700 {
          UserTablePane(opsFirst: true, compact: true).frame(minWidth: 280, idealWidth: 460)
        }
      }
    }
  }
}

struct ClassicTranscript: View {
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    let messages = state.visibleMessages
    let firstUnread = messages.firstUnreadID
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 3) {
        ForEach(messages) { message in
          if message.id == firstUnread { UnreadDivider() }
          line(message)
        }
      }
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
    }
    .defaultScrollAnchor(.bottom)
    .background(.background)
  }

  @ViewBuilder private func line(_ message: HubMessage) -> some View {
    switch message {
    case .historyStart:
      HistoryStart()
    case .status(_, let time, let text, let severity):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(time).monospacedDigit().foregroundStyle(.tertiary)
        StatusLine(text: text, severity: severity)
      }
    case .chat(_, let time, let from, let text, let thirdPerson, _):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(time).monospacedDigit().foregroundStyle(.tertiary)
        if thirdPerson {
          Text("* \(from) ").bold().italic() + Text(MessageText.attributed(text)).italic()
        } else {
          Text("<\(from)> ").bold() + Text(MessageText.attributed(text))
        }
      }
      .padding(.vertical, 1)
      .background(message.isMention ? Color.accentColor.opacity(0.12) : .clear)
    }
  }
}

/// The user list as a Table. Right-click the header to show or hide columns.
struct UserTablePane: View {
  let opsFirst: Bool
  let compact: Bool
  @Environment(HubPrototypeState.self) private var state
  @State private var sortOrder = [KeyPathComparator(\HubUser.nick, comparator: .localizedStandard)]
  @State private var columns = TableColumnCustomization<HubUser>()

  var body: some View {
    @Bindable var state = state
    VStack(spacing: 0) {
      if state.isOnline {
        table(sorted(state.visibleUsers), selection: $state.selectedUser)
      } else {
        ContentUnavailableView("No Users", systemImage: "person.2.slash", description: Text("The user list fills in once the hub is connected."))
      }
      Divider()
      Text(state.isOnline ? totals(state.visibleUsers) : "—")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
  }

  private func sorted(_ users: [HubUser]) -> [HubUser] {
    let byColumn = users.sorted(using: sortOrder)
    return opsFirst ? byColumn.sorted { $0.rank < $1.rank } : byColumn
  }

  private func table(_ users: [HubUser], selection: Binding<HubUser.ID?>) -> some View {
    Table(users, selection: selection, sortOrder: $sortOrder, columnCustomization: $columns) {
      TableColumn("Nick", value: \.nick, comparator: .localizedStandard) { user in
        Label(user.nick, systemImage: user.symbol)
          .foregroundStyle(user.flags.contains(.ignored) ? .tertiary : .primary)
      }
      .customizationID("nick")
      TableColumn("Share Size", value: \.shareSize) { Text(bytes($0.shareSize)) }.customizationID("share")
      TableColumn("Description", value: \.description).customizationID("description")
      TableColumn("Tag", value: \.tag).customizationID("tag").defaultVisibility(compact ? .hidden : .visible)
      TableColumn("Upload Speed", value: \.uploadSpeed) { Text(speed($0.uploadSpeed)) }
        .customizationID("up").defaultVisibility(compact ? .hidden : .visible)
      TableColumn("Download Speed", value: \.downloadSpeed) { Text(speed($0.downloadSpeed)) }
        .customizationID("down").defaultVisibility(.hidden)
      TableColumn("Files", value: \.files) { Text($0.files.formatted()) }
        .customizationID("files").defaultVisibility(compact ? .hidden : .visible)
      TableColumn("IP", value: \.ip4).customizationID("ip").defaultVisibility(.hidden)
      TableColumn("Country", value: \.country).customizationID("country").defaultVisibility(compact ? .hidden : .visible)
      TableColumn("Email", value: \.email).customizationID("email").defaultVisibility(.hidden)
    }
    .contextMenu(forSelectionType: HubUser.ID.self) { ids in
      if let user = HubMock.users.first(where: { ids.contains($0.id) }) { UserActions(user: user) }
    } primaryAction: { ids in
      if let user = HubMock.users.first(where: { ids.contains($0.id) }) { state.selection = .privateChat(user.nick) }
    }
  }
}

// MARK: - B — Conversation + inspector

/// Messages grouped by sender with coloured nicks, status lines centred, the
/// user list in the system inspector, grouped Operators / Bots / Users, with
/// the selected user's details under it.
struct ConversationHubView: View {
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    @Bindable var state = state
    VStack(spacing: 0) {
      ConversationTranscript()
      MessageInput()
    }
    .inspector(isPresented: $state.usersVisible) {
      UserInspector().inspectorColumnWidth(min: 220, ideal: 280, max: 420)
    }
  }
}

struct ConversationTranscript: View {
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    let messages = state.visibleMessages
    let firstUnread = messages.firstUnreadID
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
          if message.id == firstUnread { UnreadDivider().padding(.horizontal, 14) }
          row(message, startsGroup: index == 0 || messages[index - 1].sender != message.sender || message.id == firstUnread)
        }
      }
      .textSelection(.enabled)
      .padding(.vertical, 10)
    }
    .defaultScrollAnchor(.bottom)
    .background(.background)
  }

  @ViewBuilder private func row(_ message: HubMessage, startsGroup: Bool) -> some View {
    switch message {
    case .historyStart:
      HistoryStart()
    case .status(_, let time, let text, let severity):
      HStack {
        StatusLine(text: text, severity: severity)
        Text(time).font(.caption).foregroundStyle(.tertiary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
    case .chat(_, let time, let from, let text, let thirdPerson, _):
      let user = HubMock.users.first { $0.nick == from }
      VStack(alignment: .leading, spacing: 2) {
        if startsGroup {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button {
              state.selectedUser = user?.id
              state.usersVisible = true
            } label: {
              Text(from).bold().foregroundStyle(MessageText.color(for: from))
            }
            .buttonStyle(.plain)
            if user?.isOp == true { Image(systemName: "key.fill").font(.caption2).foregroundStyle(.secondary) }
            if user?.isBot == true { Image(systemName: "gearshape.fill").font(.caption2).foregroundStyle(.secondary) }
            Text(time).font(.caption).foregroundStyle(.tertiary)
          }
          .padding(.top, 8)
        }
        (thirdPerson ? Text("\(from) ").italic() + Text(MessageText.attributed(text)).italic() : Text(MessageText.attributed(text)))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14)
      .padding(.vertical, 1)
      .background(alignment: .leading) {
        if message.isMention {
          HStack(spacing: 0) {
            Rectangle().fill(Color.accentColor).frame(width: 3)
            Color.accentColor.opacity(0.1)
          }
        }
      }
    }
  }
}

struct UserInspector: View {
  @Environment(HubPrototypeState.self) private var state
  @State private var sortByShare = false

  var body: some View {
    @Bindable var state = state
    VStack(spacing: 0) {
      HStack {
        Text(state.isOnline ? totals(state.visibleUsers) : "Not connected").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
          Picker("Sort By", selection: $sortByShare) {
            Text("Nick").tag(false)
            Text("Share Size").tag(true)
          }
          .pickerStyle(.inline)
        }
        .menuStyle(.button)
        .buttonStyle(.accessoryBar)
        .labelStyle(.iconOnly)
        .fixedSize()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      Divider()
      if state.isOnline {
        list(selection: $state.selectedUser)
        if let user = HubMock.users.first(where: { $0.id == state.selectedUser }) { details(user) }
      } else {
        ContentUnavailableView("No Users", systemImage: "person.2.slash")
      }
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private func list(selection: Binding<HubUser.ID?>) -> some View {
    let users = state.visibleUsers.sorted { sortByShare ? $0.shareSize > $1.shareSize : $0.nick.localizedStandardCompare($1.nick) == .orderedAscending }
    let groups = [("Operators", users.filter(\.isOp)), ("Bots", users.filter { $0.isBot && !$0.isOp }), ("Users", users.filter { $0.rank == 2 })]
    return List(selection: selection) {
      ForEach(groups, id: \.0) { title, members in
        if !members.isEmpty {
          Section("\(title) (\(members.count.formatted()))") {
            ForEach(members) { user in
              HStack {
                Image(systemName: user.symbol).foregroundStyle(.secondary).frame(width: 16)
                Text(user.nick).foregroundStyle(user.flags.contains(.ignored) ? .tertiary : .primary)
                Spacer()
                Text(bytes(user.shareSize)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
              }
              .tag(user.id)
            }
          }
        }
      }
    }
    .contextMenu(forSelectionType: HubUser.ID.self) { ids in
      if let user = HubMock.users.first(where: { ids.contains($0.id) }) { UserActions(user: user) }
    } primaryAction: { ids in
      if let user = HubMock.users.first(where: { ids.contains($0.id) }) { state.selection = .privateChat(user.nick) }
    }
  }

  private func details(_ user: HubUser) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider()
      Label(user.nick, systemImage: user.symbol).font(.headline)
      UserDetails(user: user)
      HStack {
        Button("Message") { state.selection = .privateChat(user.nick) }
        Button("Browse Files") { state.selection = .fileList(user.nick) }
      }
      .controlSize(.small)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - C — Chat or Users

/// One full-width view at a time, picked in the toolbar. Chat is a three-column
/// log (time, right-aligned nick, text); clicking a nick opens a card. Users
/// is a full-width table with every column.
struct SwitcherHubView: View {
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    @Bindable var state = state
    Group {
      if state.showsUsersTab {
        UserTablePane(opsFirst: false, compact: false)
      } else {
        VStack(spacing: 0) {
          ColumnTranscript()
          MessageInput()
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Picker("View", selection: $state.showsUsersTab) {
          Text("Chat").tag(false)
          Text("Users (\(HubMock.users.count.formatted()))").tag(true)
        }
        .pickerStyle(.segmented)
        .fixedSize()
      }
    }
    .onChange(of: state.showsUsersTab) { if state.scopeBarVisible { state.showScopeBar() } }
  }
}

struct ColumnTranscript: View {
  @Environment(HubPrototypeState.self) private var state
  @State private var card: HubMessage.ID?

  var body: some View {
    let messages = state.visibleMessages
    let firstUnread = messages.firstUnreadID
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 2) {
        ForEach(messages) { message in
          if message.id == firstUnread { UnreadDivider() }
          row(message)
        }
      }
      .textSelection(.enabled)
      .padding(10)
    }
    .defaultScrollAnchor(.bottom)
    .background(.background)
  }

  @ViewBuilder private func row(_ message: HubMessage) -> some View {
    switch message {
    case .historyStart:
      HistoryStart()
    case .status(_, let time, let text, let severity):
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(time).monospacedDigit().foregroundStyle(.tertiary).frame(width: 44, alignment: .leading)
        Text("—").foregroundStyle(.tertiary).frame(width: 130, alignment: .trailing)
        StatusLine(text: text, severity: severity)
      }
    case .chat(let id, let time, let from, let text, let thirdPerson, _):
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(time).monospacedDigit().foregroundStyle(.tertiary).frame(width: 44, alignment: .leading)
        Button(thirdPerson ? "•" : from) { card = id }
          .buttonStyle(.plain)
          .bold()
          .foregroundStyle(MessageText.color(for: from))
          .lineLimit(1)
          .frame(width: 130, alignment: .trailing)
          .popover(isPresented: .init(get: { card == id }, set: { if !$0 { card = nil } })) { nickCard(from) }
        (thirdPerson ? Text("\(from) ").italic() + Text(MessageText.attributed(text)).italic() : Text(MessageText.attributed(text)))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.vertical, 1)
      .background(message.isMention ? Color.accentColor.opacity(0.12) : .clear)
    }
  }

  @ViewBuilder private func nickCard(_ nick: String) -> some View {
    if let user = HubMock.users.first(where: { $0.nick == nick }) {
      VStack(alignment: .leading, spacing: 10) {
        Label(user.nick, systemImage: user.symbol).font(.headline)
        UserDetails(user: user)
        HStack {
          Button("Message") { state.selection = .privateChat(nick) }
          Button("Browse Files") { state.selection = .fileList(nick) }
          Button("Show in Users") {
            state.selectedUser = user.id
            state.showsUsersTab = true
          }
        }
        .controlSize(.small)
      }
      .padding()
      .frame(width: 340)
    }
  }
}
