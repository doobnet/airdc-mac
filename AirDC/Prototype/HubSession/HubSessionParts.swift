// PROTOTYPE — throwaway. Pieces every variant shares, so the variants differ
// in layout and transcript style only: the connect-state banner, the scope
// bar, the message input, message text with highlights, user actions and
// hub info.

import SwiftUI

// MARK: - Connect state

struct ConnectBanner: View {
  @Environment(HubPrototypeState.self) private var state
  @State private var password = ""

  var body: some View {
    switch state.connectState {
    case .connected:
      EmptyView()
    case .connecting:
      banner("Connecting to \(state.hubURL)…", symbol: "arrow.triangle.2.circlepath", tint: .secondary) {
        ProgressView().controlSize(.small)
      }
    case .password:
      banner("Sweden's Finest asks for the password for “\(HubMock.myNick)”.", symbol: "key", tint: .orange) {
        SecureField("Password", text: $password).frame(width: 180)
        Button("Log In") { state.connectState = .connected }.disabled(!state.permissions.hubsEdit || password.isEmpty)
      }
    case .redirect:
      banner("The hub redirects you to \(HubMock.redirectURL).", symbol: "arrow.uturn.right", tint: .orange) {
        Button("Follow") {
          state.redirectFollowed = true
          state.connectState = .connected
        }
        .disabled(!state.permissions.hubsEdit)
      }
    case .keyprintMismatch:
      banner("The hub's certificate doesn't match the keyprint saved for it. The connection was refused — check the hub's address in the Web UI.", symbol: "exclamationmark.shield", tint: .red) {
        Button("Reconnect") { state.connectState = .connecting }.disabled(!state.permissions.hubsEdit)
      }
    case .disconnected:
      banner("Disconnected: Connection timed out.", symbol: "network.slash", tint: .secondary) {
        Button("Reconnect") { state.connectState = .connecting }.disabled(!state.permissions.hubsEdit)
      }
    }
  }

  private func banner<Actions: View>(_ text: String, symbol: String, tint: Color, @ViewBuilder actions: () -> Actions) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: symbol).foregroundStyle(tint).font(.title3)
        VStack(alignment: .leading, spacing: 2) {
          Text(text)
          if !state.permissions.hubsEdit && state.connectState != .connecting {
            Text("Your web user can't change hubs, so ask the Daemon's owner.").font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer()
        actions()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(tint.opacity(0.08))
      Divider()
    }
  }
}

// MARK: - Scope bar

struct ScopeBar: View {
  @Environment(HubPrototypeState.self) private var state
  @FocusState private var focused: Bool

  var body: some View {
    @Bindable var state = state
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        ForEach(state.scopes, id: \.self) { scope in
          Button(scope) { state.scope = scope }
            .buttonStyle(.accessoryBar)
            .background(state.scope == scope ? Color.primary.opacity(0.12) : .clear, in: .rect(cornerRadius: 5))
        }
        Spacer()
        TextField("Filter", text: $state.filter)
          .textFieldStyle(.roundedBorder)
          .frame(width: 220)
          .focused($focused)
          .onExitCommand { state.hideScopeBar() }
        Button("Done") { state.hideScopeBar() }.controlSize(.small)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(.bar)
      Divider()
    }
    .onAppear { focused = true }
  }
}

// MARK: - Input

struct MessageInput: View {
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    @Bindable var state = state
    VStack(spacing: 0) {
      Divider()
      Group {
        if !state.permissions.hubsSend {
          Label("Your web user can read this hub but can't send messages.", systemImage: "lock")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          TextField(state.isOnline ? "Message Sweden's Finest" : "Not connected", text: $state.draft, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...5)
            .disabled(!state.isOnline)
            .onSubmit { state.send() }
        }
      }
      .padding(8)
    }
  }
}

// MARK: - Message text

enum MessageText {
  /// Builds the text with the Daemon's highlights applied: links, magnets
  /// (shown by name, green when already shared or queued — the `dupe` field),
  /// and mentions of the user's own nick. Positions from the Daemon are UTF-8
  /// byte offsets; this mock finds them by scanning instead.
  static func attributed(_ text: String) -> AttributedString {
    var result = AttributedString()
    for (index, word) in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
      if index > 0 { result += AttributedString(" ") }
      result += piece(String(word))
    }
    return result
  }

  private static func piece(_ word: String) -> AttributedString {
    if word.hasPrefix("magnet:"), let name = word.components(separatedBy: "dn=").last {
      var piece = AttributedString("⬇︎ \(name) (700 MiB)")
      piece.link = URL(string: word)
      piece.foregroundColor = .green
      return piece
    }
    if word.hasPrefix("http"), let url = URL(string: word) {
      var piece = AttributedString(word)
      piece.link = url
      return piece
    }
    var piece = AttributedString(word)
    if word.lowercased().hasPrefix(HubMock.myNick) {
      piece.font = .body.bold()
      piece.foregroundColor = .accentColor
    }
    return piece
  }

  static func color(for nick: String) -> Color {
    let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .brown, .mint]
    return palette[abs(nick.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % palette.count]
  }
}

struct StatusLine: View {
  let text: String
  let severity: Severity

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.callout)
      .foregroundStyle(severity == .warning ? .orange : severity == .error ? .red : .secondary)
  }

  private var symbol: String {
    switch severity {
    case .verbose, .info: "info.circle"
    case .warning: "exclamationmark.triangle"
    case .error: "xmark.octagon"
    }
  }
}

struct HistoryStart: View {
  var body: some View {
    Text("Older messages aren't kept by the Daemon.")
      .font(.caption)
      .foregroundStyle(.tertiary)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
  }
}

struct UnreadDivider: View {
  var body: some View {
    HStack {
      VStack { Divider().overlay(.red) }
      Text("New Messages").font(.caption.bold()).foregroundStyle(.red)
      VStack { Divider().overlay(.red) }
    }
    .padding(.vertical, 4)
  }
}

extension Array where Element == HubMessage {
  var firstUnreadID: Int? { first(where: \.isUnread)?.id }
}

// MARK: - Users

struct UserActions: View {
  let user: HubUser
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    Button("Send Private Message") { state.selection = .privateChat(user.nick) }
    Button("Browse File List") { state.selection = .fileList(user.nick) }
    Button("Mention in Chat") { state.draft += "\(user.nick): " }.disabled(!state.permissions.hubsSend)
    Divider()
    Button("Grant Extra Slot") {}.disabled(!state.permissions.settingsEdit)
    Button(user.flags.contains(.ignored) ? "Unignore" : "Ignore") {}.disabled(!state.permissions.settingsEdit)
    Divider()
    Button("Copy Nick") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(user.nick, forType: .string)
    }
  }
}

struct UserDetails: View {
  let user: HubUser

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
      row("Description", user.description)
      row("Shared", "\(bytes(user.shareSize)) in \(user.files.formatted()) files")
      row("Client", user.tag)
      row("Speed", "↑ \(speed(user.uploadSpeed))  ↓ \(speed(user.downloadSpeed))")
      row("IP", "\(user.ip4) (\(user.country))")
      if !user.email.isEmpty { row("Email", user.email) }
      row("Mode", user.flags.contains(.passive) ? "Passive" : "Active")
    }
    .font(.callout)
    .textSelection(.enabled)
  }

  @ViewBuilder private func row(_ label: String, _ value: String) -> some View {
    if !value.isEmpty {
      GridRow {
        Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
        Text(value).lineLimit(2)
      }
    }
  }
}

func totals(_ users: [HubUser]) -> String {
  let share = users.reduce(Int64(0)) { $0 + $1.shareSize }
  return "\(users.count.formatted()) users · \(bytes(share))"
}

// MARK: - Hub info

struct HubInfo: View {
  @Environment(HubPrototypeState.self) private var state

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(HubMock.hubName).font(.title2.bold())
      Text(HubMock.topic).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      Divider()
      Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
        GridRow { Text("Address").foregroundStyle(.secondary); Text(state.hubURL).textSelection(.enabled) }
        GridRow { Text("Security").foregroundStyle(.secondary); Text("TLS 1.3, keyprint trusted") }
        GridRow { Text("Users").foregroundStyle(.secondary); Text(totals(HubMock.users)) }
        GridRow { Text("Nick").foregroundStyle(.secondary); Text(HubMock.myNick) }
        GridRow { Text("Share Profile").foregroundStyle(.secondary); Text("Default") }
        GridRow { Text("Show Joins").foregroundStyle(.secondary); Text("Off") }
      }
      .font(.callout)
    }
    .padding()
    .frame(width: 380)
  }
}
