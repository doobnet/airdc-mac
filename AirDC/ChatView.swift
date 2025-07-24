import SwiftUI

struct ChatView: View {
  var selectedItem: SidebarItem?
  @Binding var messages: [String: [String]]
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
      .background(Color(NSColor.textBackgroundColor))

      Divider()

      HStack {
        TextField("Message", text: $messageText)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .onSubmit {
            sendMessage()
          }
        Button("Send") {
          sendMessage()
        }
      }
      .padding(8)
    }
    .background(Color(NSColor.windowBackgroundColor))
    .cornerRadius(4)
  }

  private func sendMessage() {
    guard let key = selectedItem?.title, !messageText.isEmpty else { return }
    messages[key, default: []].append("You: \(messageText)")
    messageText = ""
  }
}
