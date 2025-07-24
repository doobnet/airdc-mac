import SwiftUI

struct SidebarItem: Identifiable, Hashable {
  var id = UUID()
  var title: String
  var children: [SidebarItem]? = nil
}

let sidebarData: [SidebarItem] = [
  SidebarItem(
    title: "Hubs",
    children: [
      SidebarItem(title: "Item 1"),
      SidebarItem(title: "Item 2"),
      SidebarItem(title: "Item 3"),
      SidebarItem(title: "Item 4"),
    ]
  ),
  SidebarItem(
    title: "Messages",
    children: [
      SidebarItem(title: "Item A"),
      SidebarItem(title: "Item B"),
    ]
  ),
  SidebarItem(
    title: "Filelists",
    children: [
      SidebarItem(title: "Item A"),
      SidebarItem(title: "Item B"),
    ]
  ),
  SidebarItem(
    title: "Files",
    children: [
      SidebarItem(title: "Item A"),
      SidebarItem(title: "Item B"),
    ]
  ),
]

struct SidebarView: View {
  @Binding var selection: SidebarItem?

  var body: some View {
    List(selection: $selection) {
      OutlineGroup(sidebarData, children: \.children) { item in
        Label(
          item.title,
          systemImage: item.children == nil ? "circle.fill" : "folder"
        )
        .foregroundColor(item.children == nil ? .pink : .primary)
      }
    }
    .listStyle(SidebarListStyle())
  }
}

#Preview {
  @Previewable @State var selectedSidebarItem: SidebarItem? = nil
  SidebarView(selection: $selectedSidebarItem)
}
