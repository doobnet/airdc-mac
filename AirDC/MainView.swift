import SwiftUI

struct MainView: View {
  @State private var selectedSidebarItem: SidebarItem? = nil

  var body: some View {
    NavigationSplitView {
      SidebarView(selection: $selectedSidebarItem)
        .frame(minWidth: 200)
    } detail: {
      VStack(spacing: 0) {
        TopBarView()

        VSplitView {
          HubView(sidebarSelection: $selectedSidebarItem)
        }

        Divider()
        QueueView()
      }
    }
  }
}

#Preview {
  MainView()
}
