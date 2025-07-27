import SplitView
import SwiftUI

struct HubView: View {
  @Binding var sidebarSelection: SidebarItem?

  @State private var chatMessages: [String: [String]] = [
    "Item 2": ["Item 2: Welcome to the hub!", "Item 2: Rules are strict here."]
  ]

  @State private var chatViewVisible: Bool = true
  @State private var usersViewVisible: Bool = true
  @ObservedObject var hide = SideHolder()

  var body: some View {
    HSplit {
      ChatView(selectedItem: sidebarSelection, messages: $chatMessages)
        .frame(minWidth: 100)
    }

    right: {
      UsersView().frame(minWidth: 50)
    }
    .hide(hide)
    .overlay(alignment: .bottomTrailing) {
      HStack {
        Button {
          withAnimation {
            hide.toggle(.primary)
          }
        } label: {
          Image(systemName: "square.leadingthird.inset.filled")
        }
        .buttonStyle(.icon(isActive: !(hide.side?.isPrimary ?? false)))

        Button {
          withAnimation {
            hide.toggle(.secondary)
          }
        } label: {
          Image(systemName: "square.trailingthird.inset.filled")
        }
        .buttonStyle(.icon(isActive: !(hide.side?.isSecondary ?? false)))
      }
    }
  }
}

#Preview {
  @Previewable @State var selectedSidebarItem: SidebarItem? = nil
  HubView(sidebarSelection: $selectedSidebarItem)
}
