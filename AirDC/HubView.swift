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
    PaneView { pane in
      ChatView(selectedItem: sidebarSelection, messages: $chatMessages, otherViewCollapsed: usersViewCollapsed)
        .frame(minWidth: 100)

      pane.bottomBar {
        HStack {
          TextField("Message", text: .constant(""))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .onSubmit {
              print("Send message")
            }
          Button("Send") {
            print("Send message")
          }
        }
      }
    } trailing: { pane in
      UsersView().frame(minWidth: 50)

      pane.bottomBar {
        HStack {
          Spacer()
          Text("709 Users")
            .font(.caption)
          Divider()
          Text("3.54 PiB (3.04 TiB/user)")
            .font(.caption)
        }
      }
    }
  }
}

#Preview {
  @Previewable @State var selectedSidebarItem: SidebarItem? = nil
  HubView(sidebarSelection: $selectedSidebarItem)
}
