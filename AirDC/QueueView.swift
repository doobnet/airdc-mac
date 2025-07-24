import SwiftUI

struct QueueView: View {
  @State private var downloads: [DownloadItem] = [
    DownloadItem(
      name: "Item 2",
      size: "349.68 MiB",
      content: "1 folder, 10 files",
      status: "Waiting (92.2%)",
      timeLeft: "1 minute",
      sources: "1/1 Online",
      priority: "High (auto)",
      speed: "15.68 MiB/s",
      added: "a day ago",
      finished: "a day ago",
      user: "Foobar",
      segment: "14.81 MiB",
      flags: "",
      ip: "84.123.4.5"
    )
  ]

  var body: some View {
    Table(downloads) {
      TableColumn("Name", value: \.name)
      TableColumn("Size", value: \.size)
      TableColumn("Type/Content", value: \.content)
      TableColumn("Status", value: \.status)
      TableColumn("Sources", value: \.sources)
      TableColumn("Time Left", value: \.timeLeft)
      TableColumn("Speed", value: \.speed)
      TableColumn("Priority", value: \.priority)
      TableColumn("Added", value: \.added)
      TableColumn("Finished", value: \.finished)
    }
    .frame(minHeight: 120)
  }
}

#Preview(traits: PreviewTrait.fixedLayout(width: 1000, height: 300)) {
  QueueView()
}
