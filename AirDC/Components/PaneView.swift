import SwiftUI

class Pane {
  var content: AnyView? = nil

  func bottomBar<Content: View>(
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    self.content = AnyView(content())
    return EmptyView()
  }
}

fileprivate struct Model<Content: View> {
  let content: Content
  let pane: Pane = Pane()
  @State var isCollapsed: Bool = false
}

struct PaneView<Leading: View, Trailing: View>: View {
  init(
    @ViewBuilder leading: @escaping (Pane) -> Leading,
    @ViewBuilder trailing: @escaping (Pane) -> Trailing
  ) {
    self.leading = leading
    self.trailing = trailing
  }

  init(
    @ViewBuilder leading: @escaping () -> Leading,
    @ViewBuilder trailing: @escaping () -> Trailing
  ) {
    self.init(leading: { _ in leading() }, trailing: { _ in trailing() })
  }

  var body: some View {
    SplitView(axis: .horizontal) {
      leading(paneLeading)
        .collapsable()
        .collapsed($leadingCollapsed)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if let content = paneLeading.content {
            content
          } else {
            EmptyView()
          }
        }

      trailing(paneTrailing)
        .collapsable()
        .collapsed($trailingCollapsed)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if let content = paneTrailing.content {
            content
          } else {
            EmptyView()
          }
        }
    }
    .overlay(alignment: .bottomTrailing) {
      Group {
        HStack(spacing: 5) {
          Divider()

          Button {
            leadingCollapsed.toggle()

            if trailingCollapsed && leadingCollapsed {
              trailingCollapsed.toggle()
            }
          } label: {
            Image(systemName: "square.leadingthird.inset.filled")
          }
          .buttonStyle(.icon(isActive: !leadingCollapsed))

          Button {
            trailingCollapsed.toggle()

            if trailingCollapsed && leadingCollapsed {
              leadingCollapsed.toggle()
            }
          } label: {
            Image(systemName: "square.trailingthird.inset.filled")
          }
          .buttonStyle(.icon(isActive: !trailingCollapsed))
        }
        .buttonStyle(.icon(size: 24))
        .padding(.horizontal, 5)
        .padding(.vertical, 8)
        .frame(maxHeight: 27)
        .background(.windowBackground)
      }
    }
  }

  private let leading: (Pane) -> Leading
  private let trailing: (Pane) -> Trailing
  private var paneLeading = Pane()
  private var paneTrailing = Pane()
  @State private var leadingCollapsed: Bool = false
  @State private var trailingCollapsed: Bool = false
}

#Preview {
  let users: [User] = [
    User(
      nick: "Item 2",
      shareSize: "5.15 GiB",
      description: "[ BOT ]",
      tag: "< Bot >",
      uploadSpeed: "100.00 Mbit/s",
      downloadSpeed: "100.00 Mbit/s",
      ipV4: "82.123.156.78",
      ipV6: "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
      files: "77"
    )
  ]

  PaneView { pane in
    Table(users) {
      TableColumn("Nick", value: \.nick)
      TableColumn("Share Size", value: \.shareSize)
      TableColumn("Description", value: \.description)
    }.frame(minWidth: 200)

    pane.bottomBar {
      Text("Users Online: \(users.count)")
    }
  } trailing: { pane in
    Table(users) {
      TableColumn("Nick", value: \.nick)
      TableColumn("Share Size", value: \.shareSize)
      TableColumn("Description", value: \.description)
    }.frame(minWidth: 200)

    pane.bottomBar {
      Text("Foobar: \(users.count)")
    }
  }
}
