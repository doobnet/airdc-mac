import SwiftUI

struct UsersView: View {
  @State private var filter: String = ""
  @State private var users: [User] = [
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

  var body: some View {
    VStack(spacing: 0) {
      Table(users) {
        TableColumn("Nick", value: \.nick)
        TableColumn("Share Size", value: \.shareSize)
        TableColumn("Description", value: \.description)
        TableColumn("Tag", value: \.tag)
        TableColumn("Upload Speed", value: \.uploadSpeed)
        TableColumn("Download Speed", value: \.downloadSpeed)
        TableColumn("IP (v4)", value: \.ipV4)
        TableColumn("IP (v6)", value: \.ipV6)
        TableColumn("Files", value: \.files)
      }
    }.background(.windowBackground)
  }
}

#Preview {
  UsersView()
}
