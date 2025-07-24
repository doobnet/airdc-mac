import SwiftUI

struct TopBarView: View {
  @State private var searchText = ""

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text("Foobar")
          .font(.title2)
          .bold()
        Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit...")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      TextField("Search Term", text: $searchText)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .frame(width: 200)

      Button(action: {}) {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(PlainButtonStyle())
    }
    .padding(.bottom)
  }
}

#Preview {
  TopBarView()
}
