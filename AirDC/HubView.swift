import SwiftUI

struct HubView: View {
  @Binding var sidebarSelection: SidebarItem?

  @State private var chatMessages: [String: [String]] = [
    "Item 2": ["Item 2: Welcome to the hub!", "Item 2: Rules are strict here."]
  ]

  var body: some View {
    ChatView(selectedItem: sidebarSelection, messages: $chatMessages)
      .frame(minHeight: 150)

    UsersView()
  }
}

#Preview {
  @Previewable @State var selectedSidebarItem: SidebarItem? = nil
  HubView(sidebarSelection: $selectedSidebarItem)
}
