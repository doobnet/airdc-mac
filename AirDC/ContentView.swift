import SwiftUI

struct ContentView: View {
    @EnvironmentObject var client: Client

    var body: some View {
        VStack {
            Button("Get Favorite Hubs") {
                Task {
                    let result = try! await client.getFavoriteHubs()
                    print(result)
                }
            }
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
