import Foundation

struct User: Identifiable {
  var id = UUID()
  var nick: String
  var shareSize: String
  var description: String
  var tag: String
  var uploadSpeed: String
  var downloadSpeed: String
  var ipV4: String
  var files: Int
}
