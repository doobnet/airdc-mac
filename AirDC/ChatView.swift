import SwiftUI

struct ChatView: View {
  var selectedItem: SidebarItem?
  @Binding var messages: [String: [String]]
  let otherViewCollapsed: Bool
  @State private var messageText = ""

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(messages[selectedItem?.title ?? ""] ?? [], id: \.self) {
            msg in
            Text(msg)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding()
      }
      .background(.windowBackground)
    }
    .background(.windowBackground)
    .cornerRadius(4)
  }

  private func sendMessage() {
    guard let key = selectedItem?.title, !messageText.isEmpty else { return }
    messages[key, default: []].append("You: \(messageText)")
    messageText = ""
  }
}

#Preview {
  @Previewable @State  var chatMessages: [String: [String]] = [
    "Item 2": ["Item 2: Welcome to the hub!", "Item 2: Rules are strict here."]
  ]

  ChatView(messages: $chatMessages, otherViewCollapsed: false)
}
