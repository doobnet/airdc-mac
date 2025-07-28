import SplitView
import SwiftUI

struct HubView: View {
  @Binding var sidebarSelection: SidebarItem?

  @State private var chatMessages: [String: [String]] = [
    "Item 2": ["Item 2: Welcome to the hub!", "Item 2: Rules are strict here."]
  ]

  @State private var chatViewCollapsed: Bool = false
  @State private var usersViewCollapsed: Bool = false

  var body: some View {
    SplitView(axis: .horizontal) {
      ChatView(selectedItem: sidebarSelection, messages: $chatMessages, otherViewCollapsed: usersViewCollapsed)
        .frame(minWidth: 100)
        .collapsable()
        .collapsed($chatViewCollapsed)

      UsersView().frame(minWidth: 50)
        .collapsable()
        .collapsed($usersViewCollapsed)
    }
    .animation(.default, value: chatViewCollapsed)
    .animation(.default, value: usersViewCollapsed)
    .overlay(alignment: .bottomTrailing) {
      Group {
        HStack(spacing: 5) {
          Divider()

          Button {
            chatViewCollapsed.toggle()

            if usersViewCollapsed && chatViewCollapsed {
              usersViewCollapsed.toggle()
            }
          } label: {
            Image(systemName: "square.leadingthird.inset.filled")
          }
          .buttonStyle(.icon(isActive: !chatViewCollapsed))

          Button {
            usersViewCollapsed.toggle()

            if usersViewCollapsed && chatViewCollapsed {
              chatViewCollapsed.toggle()
            }
          } label: {
            Image(systemName: "square.trailingthird.inset.filled")
          }
          .buttonStyle(.icon(isActive: !usersViewCollapsed))
        }
        .buttonStyle(.icon(size: 24))
        .padding(.horizontal, 5)
        .padding(.vertical, 8)
        .frame(maxHeight: 27)
        .background(.windowBackground)
      }.frame(maxHeight: 40)
    }
  }
}

#Preview {
  @Previewable @State var selectedSidebarItem: SidebarItem? = nil
  HubView(sidebarSelection: $selectedSidebarItem)
}
