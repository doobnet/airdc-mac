import SwiftUI

struct MainWindowView: View {
  @State private var selectedSidebarItem: SidebarItem? = nil

  @State private var chatMessages: [String: [String]] = [
    "Item 2": ["Item 2: Welcome to the hub!", "Item 2: Rules are strict here."]
  ]

  @State private var peers: [User] = [
    User(
      nick: "Item 2",
      shareSize: "5.15 GiB",
      description: "[ BOT ]",
      tag: "< Bot >",
      uploadSpeed: "100.00 Mbit/s",
      downloadSpeed: "100.00 Mbit/s",
      ipV4: "82.123.156.78",
      files: 77
    )
  ]

  @State private var downloads: [DownloadItem] = [
    DownloadItem(
      name: "Item 2",
      size: "349.68 MiB",
      content: "1 folder, 10 files",
      status: "Waiting (92.2%)",
      sources: "1/1 Online",
      priority: "High (auto)",
      added: "a day ago",
      finished: "a day ago",
      user: "Foobar",
      segment: "14.81 MiB",
      flags: "",
      ip: "84.123.4.5"
    )
  ]

  var body: some View {
    NavigationSplitView {
      SidebarView(selection: $selectedSidebarItem)
        .frame(minWidth: 200)
    } detail: {
      VStack(spacing: 0) {
        TopBarView()

        VSplitView {
          ChatView(selectedItem: selectedSidebarItem, messages: $chatMessages)
            .frame(minHeight: 150)

          Table(peers) {
            TableColumn("Nick", value: \.nick)
            TableColumn("Share Size", value: \.shareSize)
            TableColumn("Description", value: \.description)
            TableColumn("Tag", value: \.tag)
            TableColumn("Upload Speed", value: \.uploadSpeed)
            TableColumn("Download Speed", value: \.downloadSpeed)
            TableColumn("IP (v4)", value: \.ipV4)
            TableColumn("Files") { peer in
              Text("\(peer.files)")
            }
          }
          .frame(minHeight: 150)
        }

        Divider()

        Table(downloads) {
          TableColumn("Name", value: \.name)
          TableColumn("Size", value: \.size)
          TableColumn("Type/Content", value: \.content)
          TableColumn("Status", value: \.status)
          TableColumn("Sources", value: \.sources)
          TableColumn("Priority", value: \.priority)
          TableColumn("Added", value: \.added)
          TableColumn("Finished", value: \.finished)
          TableColumn("User", value: \.user)
          TableColumn("Segment", value: \.segment)
          TableColumn("IP", value: \.ip)
        }
        .frame(minHeight: 120)
      }
      .padding()
    }
  }
}
